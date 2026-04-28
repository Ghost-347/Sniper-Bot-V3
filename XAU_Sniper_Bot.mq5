//+------------------------------------------------------------------+
//|                                              XAU_Sniper_Bot.mq5  |
//|                                  Copyright 2024, Quant Engineer  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Quant Engineer"
#property link      "https://www.mql5.com"
#property version   "1.20"
#property strict

/*
   SNIPER BOT SPECIFICATIONS:
   - Strategy: Liquidity Sweep + Fibonacci Retracement
   - Adaptation: ATR-based Volatility Filter & Market Structure detection
   - Profit Trap: Moves SL to lock in 30% profit when 50% of TP is reached
   - Safeguard: Pauses and notifies after X consecutive losses
   - Dashboard: Real-time stats on Win Rate, Daily Trades, and Status
*/

//--- Includes
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Input Parameters
input group "=== Risk Management ==="
input double   InpLotSize        = 0.1;      // Fixed Lot Size
input int      InpStopLossPips   = 250;      // Initial Stop Loss (Points)
input int      InpTakeProfitPips = 750;      // Take Profit (Points)
input int      InpMaxLosses      = 3;        // Max Consecutive Losses before Pause
input bool     InpSendPush       = true;     // Send Mobile Notification on Pause

input group "=== Sniper Logic (Liquidity & Fibo) ==="
input int      InpSwingPeriod    = 15;       // Bars to identify Swing High/Low
input double   InpFibLevel       = 0.618;    // Fibonacci Retracement Level
input ENUM_TIMEFRAMES InpFiboTF  = PERIOD_M5;  // Timeframe for Fibonacci Analysis
input bool     InpUseTrendFilter = true;     // Only trade in direction of H4 Trend

input group "=== Adaptive Settings (Learn & Adapt) ==="
input int      InpATRPeriod      = 14;       // ATR Period for volatility filter
input double   InpMinATR         = 60;       // Minimum ATR (Points) to allow trading (XAUUSD default)

input group "=== Profit Trap Settings ==="
input double   InpTriggerLevel   = 0.5;      // TP % to trigger profit trap (50%)
input double   InpSecureLevel    = 0.3;      // % of TP to secure (30%)

//--- Global Variables
CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symbolInfo;
int            consecutiveLosses = 0;
bool           isPaused = false;
string         botName = "XAU Sniper Bot";
int            magicNumber = 123456;

// Indicator Handles
int            handleATR;
int            handleMA_H4;

//--- Dashboard Labels
string labels[] = {"lbl_header", "lbl_winrate", "lbl_trades", "lbl_wins", "lbl_losses", "lbl_status"};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!symbolInfo.Name(_Symbol)) return(INIT_FAILED);
   
   trade.SetExpertMagicNumber(magicNumber);
   
   // Initialize Handles
   handleATR = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   handleMA_H4 = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   if(handleATR == INVALID_HANDLE || handleMA_H4 == INVALID_HANDLE)
   {
      Print("Error initializing indicators");
      return(INIT_FAILED);
   }
   
   // Create Dashboard
   CreateDashboard();
   EventSetTimer(1);
   
   Print(botName, " V1.20 initialized on ", _Symbol);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   IndicatorRelease(handleATR);
   IndicatorRelease(handleMA_H4);
   for(int i=0; i<ArraySize(labels); i++) ObjectDelete(0, labels[i]);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(isPaused) return;

   // 1. Safeguard Check
   UpdateConsecutiveLosses();
   if(consecutiveLosses >= InpMaxLosses)
   {
      isPaused = true;
      if(InpSendPush) SendNotification(botName + ": Paused on " + _Symbol + " after " + IntegerToString(consecutiveLosses) + " losses.");
      UpdateDashboard();
      return;
   }

   // 2. Manage open positions (Profit Trap)
   ManagePositions();

   // 3. Sniper Entry Check (Only if no open positions for this bot)
   if(!PositionExists())
   {
      CheckForSniperEntry();
   }
   
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Timer function for Dashboard updates                             |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Check if position exists with magic number                       |
//+------------------------------------------------------------------+
bool PositionExists()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == magicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Sniper Entry Logic                                               |
//+------------------------------------------------------------------+
void CheckForSniperEntry()
{
   // A. Adaptive Volatility Filter (ATR)
   double atrValue = GetIndicatorValue(handleATR, 0);
   if(atrValue < InpMinATR * _Point) return;

   // B. Trend Filter (H4 MA)
   bool trendBullish = true;
   if(InpUseTrendFilter)
   {
      double maValue = GetIndicatorValue(handleMA_H4, 0);
      double closeH4 = iClose(_Symbol, PERIOD_H4, 0);
      trendBullish = (closeH4 > maValue);
   }

   // C. Liquidity Sweep Detection (Swing High/Low)
   double highSeries[], lowSeries[], closeSeries[];
   ArraySetAsSeries(highSeries, true);
   ArraySetAsSeries(lowSeries, true);
   ArraySetAsSeries(closeSeries, true);
   
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, InpSwingPeriod + 1, highSeries) <= 0) return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, InpSwingPeriod + 1, lowSeries) <= 0) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 1, closeSeries) <= 0) return;

   double swingHigh = highSeries[ArrayMaximum(highSeries, 1, InpSwingPeriod)];
   double swingLow  = lowSeries[ArrayMinimum(lowSeries, 1, InpSwingPeriod)];
   
   double currentHigh = highSeries[0];
   double currentLow  = lowSeries[0];
   double currentClose = closeSeries[0];

   // D. Fibonacci Level Calculation
   double fibPriceBuy = CalculateFibLevel(InpFiboTF, true); 
   double fibPriceSell = CalculateFibLevel(InpFiboTF, false);

   // SNIPE BUY: Sweep Swing Low + Close Above + Fibo Confluence + Bullish Trend
   if(currentLow < swingLow && currentClose > swingLow && trendBullish)
   {
      if(MathAbs(currentClose - fibPriceBuy) < 150 * _Point) // Within 15 pips of Fibo
      {
         double sl = currentClose - InpStopLossPips * _Point;
         double tp = currentClose + InpTakeProfitPips * _Point;
         trade.Buy(InpLotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), sl, tp, "Sniper Buy");
      }
   }
   
   // SNIPE SELL: Sweep Swing High + Close Below + Fibo Confluence + Bearish Trend
   if(currentHigh > swingHigh && currentClose < swingHigh && !trendBullish)
   {
      if(MathAbs(currentClose - fibPriceSell) < 150 * _Point)
      {
         double sl = currentClose + InpStopLossPips * _Point;
         double tp = currentClose - InpTakeProfitPips * _Point;
         trade.Sell(InpLotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), sl, tp, "Sniper Sell");
      }
   }
}

//+------------------------------------------------------------------+
//| Get Indicator Value Helper                                       |
//+------------------------------------------------------------------+
double GetIndicatorValue(int handle, int index)
{
   double buffer[];
   if(CopyBuffer(handle, 0, index, 1, buffer) > 0) return buffer[0];
   return 0;
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci Level                                        |
//+------------------------------------------------------------------+
double CalculateFibLevel(ENUM_TIMEFRAMES tf, bool buy)
{
   double highSeries[], lowSeries[];
   if(CopyHigh(_Symbol, tf, 0, 150, highSeries) <= 0) return 0;
   if(CopyLow(_Symbol, tf, 0, 150, lowSeries) <= 0) return 0;
   
   double high = highSeries[ArrayMaximum(highSeries)];
   double low  = lowSeries[ArrayMinimum(lowSeries)];
   
   if(buy) return low + (high - low) * InpFibLevel; 
   else    return high - (high - low) * InpFibLevel; 
}

//+------------------------------------------------------------------+
//| Manage Positions (Profit Trap Logic)                             |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == magicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         long type = PositionGetInteger(POSITION_TYPE);
         
         if(tp == 0) continue;
         
         double totalProfitPoints = MathAbs(tp - entry);
         double currentProfitPoints = MathAbs(currentPrice - entry);
         
         // PROFIT TRAP: If 50% of TP reached
         if(currentProfitPoints >= totalProfitPoints * InpTriggerLevel)
         {
            double newSL;
            if(type == POSITION_TYPE_BUY)
               newSL = entry + (totalProfitPoints * InpSecureLevel);
            else
               newSL = entry - (totalProfitPoints * InpSecureLevel);
               
            // Only move SL if it improves protection
            if((type == POSITION_TYPE_BUY && newSL > sl) || 
               (type == POSITION_TYPE_SELL && (newSL < sl || sl == 0)))
            {
               if(trade.PositionModify(ticket, newSL, tp))
                  Print("Profit Trap: SL moved to secure ", InpSecureLevel*100, "% profit.");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update Consecutive Loss Counter                                  |
//+------------------------------------------------------------------+
void UpdateConsecutiveLosses()
{
   if(!HistorySelect(TimeCurrent() - 86400 * 3, TimeCurrent())) return;
   int totalDeals = HistoryDealsTotal();
   consecutiveLosses = 0;
   
   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetSymbol(ticket) == _Symbol && HistoryDealGetInteger(ticket, DEAL_MAGIC) == magicNumber)
      {
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT)
         {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            if(profit < 0) consecutiveLosses++;
            else if(profit > 0) break; // Reset on win
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Dashboard Functions                                              |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   int x = 10, y = 30, step = 25;
   for(int i=0; i<ArraySize(labels); i++)
   {
      ObjectCreate(0, labels[i], OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, labels[i], OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, labels[i], OBJPROP_YDISTANCE, y + (i * step));
      ObjectSetInteger(0, labels[i], OBJPROP_COLOR, clrWhite);
      ObjectSetString(0, labels[i], OBJPROP_FONT, "Trebuchet MS");
      ObjectSetInteger(0, labels[i], OBJPROP_FONTSIZE, 11);
   }
}

void UpdateDashboard()
{
   if(!HistorySelect(TimeCurrent() - 86400, TimeCurrent())) return;
   int trades = 0, wins = 0, losses = 0;
   
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetSymbol(ticket) == _Symbol && HistoryDealGetInteger(ticket, DEAL_MAGIC) == magicNumber)
      {
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT)
         {
            trades++;
            if(HistoryDealGetDouble(ticket, DEAL_PROFIT) >= 0) wins++;
            else losses++;
         }
      }
   }
   
   double winRate = (trades > 0) ? (double)wins/trades * 100 : 0;
   
   ObjectSetString(0, "lbl_header", OBJPROP_TEXT, "--- " + botName + " DASHBOARD ---");
   ObjectSetString(0, "lbl_winrate", OBJPROP_TEXT, "Win Rate: " + DoubleToString(winRate, 2) + "%");
   ObjectSetString(0, "lbl_trades", OBJPROP_TEXT, "Daily Trades: " + IntegerToString(trades));
   ObjectSetString(0, "lbl_wins", OBJPROP_TEXT, "Wins: " + IntegerToString(wins));
   ObjectSetString(0, "lbl_losses", OBJPROP_TEXT, "Losses: " + IntegerToString(losses));
   
   string status = isPaused ? "PAUSED (Too Many Losses)" : "SNIPING ACTIVE";
   color statusColor = isPaused ? clrOrangeRed : clrSpringGreen;
   ObjectSetString(0, "lbl_status", OBJPROP_TEXT, "Status: " + status);
   ObjectSetInteger(0, "lbl_status", OBJPROP_COLOR, statusColor);
}
