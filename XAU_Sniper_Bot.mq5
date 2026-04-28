//+------------------------------------------------------------------+
//|                                              XAU_Sniper_Bot.mq5  |
//|                                  Copyright 2024, Quant Engineer  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Quant Engineer"
#property link      "https://www.mql5.com"
#property version   "1.90"
#property strict

//--- Includes
#include <Trade\Trade.mqh>

//--- Input Parameters (No 'group' keyword for maximum compatibility)
input double   InpLotSize        = 0.1;      // Fixed Lot Size
input int      InpStopLossPips   = 250;      // Initial Stop Loss (Points)
input int      InpTakeProfitPips = 750;      // Take Profit (Points)
input int      InpMaxLosses      = 3;        // Max Consecutive Losses before Pause
input bool     InpSendPush       = true;     // Send Mobile Notification on Pause

input int      InpSwingPeriod    = 15;       // Bars to identify Swing High/Low
input double   InpFibLevel       = 0.618;    // Fibonacci Retracement Level
input ENUM_TIMEFRAMES InpFiboTF  = PERIOD_M5;  // Timeframe for Fibonacci Analysis
input bool     InpUseTrendFilter = true;     // Only trade in direction of H4 Trend

input int      InpATRPeriod      = 14;       // ATR Period for volatility filter
input double   InpMinATR         = 60;       // Minimum ATR (Points) to allow trading

input double   InpTriggerLevel   = 0.5;      // TP % to trigger profit trap (50%)
input double   InpSecureLevel    = 0.3;      // % of TP to secure (30%)

//--- Global Variables
CTrade         trade;
int            consecutiveLosses = 0;
bool           isPaused = false;
string         botName = "XAU Sniper Bot";
int            magicNumber = 123456;

// Indicator Handles
int            handleATR = INVALID_HANDLE;
int            handleMA_H4 = INVALID_HANDLE;

//--- Dashboard Labels
string lbl_0 = "lbl_header";
string lbl_1 = "lbl_winrate";
string lbl_2 = "lbl_trades";
string lbl_3 = "lbl_wins";
string lbl_4 = "lbl_losses";
string lbl_5 = "lbl_status";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(magicNumber);
   
   // Initialize Handles
   handleATR = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   handleMA_H4 = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   if(handleATR == INVALID_HANDLE || handleMA_H4 == INVALID_HANDLE)
   {
      Print("Error: Failed to initialize indicators.");
      return(INIT_FAILED);
   }
   
   CreateDashboard();
   EventSetTimer(1);
   
   Print(botName, " V1.90 initialized on ", _Symbol);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
   if(handleMA_H4 != INVALID_HANDLE) IndicatorRelease(handleMA_H4);
   
   ObjectDelete(0, lbl_0);
   ObjectDelete(0, lbl_1);
   ObjectDelete(0, lbl_2);
   ObjectDelete(0, lbl_3);
   ObjectDelete(0, lbl_4);
   ObjectDelete(0, lbl_5);
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
      if(InpSendPush) SendNotification(botName + ": Safeguard activated on " + _Symbol + ". Bot paused.");
      UpdateDashboard();
      return;
   }

   // 2. Manage open positions (Profit Trap)
   ManagePositions();

   // 3. Sniper Entry Check
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
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetInteger(POSITION_MAGIC) == magicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
               return true;
         }
      }
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
   if(atrValue <= 0 || atrValue < (InpMinATR * _Point)) return;

   // B. Trend Filter (H4 MA)
   bool trendBullish = true;
   if(InpUseTrendFilter)
   {
      double maValue = GetIndicatorValue(handleMA_H4, 0);
      double closeH4 = GetClose(_Symbol, PERIOD_H4, 0);
      if(maValue > 0) trendBullish = (closeH4 > maValue);
   }

   // C. Liquidity Sweep Detection (Swing High/Low)
   double highSeries[], lowSeries[], closeSeries[];
   ArraySetAsSeries(highSeries, true);
   ArraySetAsSeries(lowSeries, true);
   ArraySetAsSeries(closeSeries, true);
   
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, InpSwingPeriod + 1, highSeries) < (InpSwingPeriod + 1)) return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, InpSwingPeriod + 1, lowSeries) < (InpSwingPeriod + 1)) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 1, closeSeries) < 1) return;

   int maxIdx = ArrayMaximum(highSeries, 1, InpSwingPeriod);
   int minIdx = ArrayMinimum(lowSeries, 1, InpSwingPeriod);
   
   if(maxIdx < 0 || minIdx < 0) return;

   double swingHigh = highSeries[maxIdx];
   double swingLow  = lowSeries[minIdx];
   
   double currentHigh = highSeries[0];
   double currentLow  = lowSeries[0];
   double currentClose = closeSeries[0];

   // D. Fibonacci Level Calculation
   double fibPriceBuy = CalculateFibLevel(InpFiboTF, true); 
   double fibPriceSell = CalculateFibLevel(InpFiboTF, false);

   // SNIPE BUY
   if(currentLow < swingLow && currentClose > swingLow && trendBullish)
   {
      if(fibPriceBuy > 0 && MathAbs(currentClose - fibPriceBuy) < (150 * _Point))
      {
         double sl = currentClose - (InpStopLossPips * _Point);
         double tp = currentClose + (InpTakeProfitPips * _Point);
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "Sniper Buy");
      }
   }
   
   // SNIPE SELL
   if(currentHigh > swingHigh && currentClose < swingHigh && !trendBullish)
   {
      if(fibPriceSell > 0 && MathAbs(currentClose - fibPriceSell) < (150 * _Point))
      {
         double sl = currentClose + (InpStopLossPips * _Point);
         double tp = currentClose - (InpTakeProfitPips * _Point);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "Sniper Sell");
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
//| Get Close Price Helper                                           |
//+------------------------------------------------------------------+
double GetClose(string symbol, ENUM_TIMEFRAMES tf, int index)
{
   double close[];
   if(CopyClose(symbol, tf, index, 1, close) > 0) return close[0];
   return 0;
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci Level                                        |
//+------------------------------------------------------------------+
double CalculateFibLevel(ENUM_TIMEFRAMES tf, bool buy)
{
   double highSeries[], lowSeries[];
   if(CopyHigh(_Symbol, tf, 0, 150, highSeries) < 150) return 0;
   if(CopyLow(_Symbol, tf, 0, 150, lowSeries) < 150) return 0;
   
   int maxIdx = ArrayMaximum(highSeries, 0, 150);
   int minIdx = ArrayMinimum(lowSeries, 0, 150);
   if(maxIdx < 0 || minIdx < 0) return 0;

   double high = highSeries[maxIdx];
   double low  = lowSeries[minIdx];
   
   if(buy) return low + (high - low) * InpFibLevel; 
   else    return high - (high - low) * InpFibLevel; 
}

//+------------------------------------------------------------------+
//| Manage Positions (Profit Trap Logic)                             |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetInteger(POSITION_MAGIC) == magicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
               double entry = PositionGetDouble(POSITION_PRICE_OPEN);
               double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
               double sl = PositionGetDouble(POSITION_SL);
               double tp = PositionGetDouble(POSITION_TP);
               long type = PositionGetInteger(POSITION_TYPE);
               
               if(tp <= 0) continue;
               
               double totalProfitPoints = MathAbs(tp - entry);
               double currentProfitPoints = MathAbs(currentPrice - entry);
               
               if(currentProfitPoints >= (totalProfitPoints * InpTriggerLevel))
               {
                  double newSL = 0;
                  if(type == (long)POSITION_TYPE_BUY)
                     newSL = entry + (totalProfitPoints * InpSecureLevel);
                  else
                     newSL = entry - (totalProfitPoints * InpSecureLevel);
                  
                  bool better = false;
                  if(type == (long)POSITION_TYPE_BUY && newSL > sl) better = true;
                  if(type == (long)POSITION_TYPE_SELL && (newSL < sl || sl <= 0)) better = true;

                  if(better && newSL > 0)
                  {
                     trade.PositionModify(ticket, newSL, tp);
                  }
               }
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
   if(!HistorySelect(TimeCurrent() - (86400 * 3), TimeCurrent())) return;
   int totalDeals = HistoryDealsTotal();
   consecutiveLosses = 0;
   
   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         if(HistoryDealSelect(ticket))
         {
            if(HistoryDealGetSymbol(ticket) == _Symbol && HistoryDealGetInteger(ticket, DEAL_MAGIC) == magicNumber)
            {
               long entryType = HistoryDealGetInteger(ticket, DEAL_ENTRY);
               if(entryType == (long)DEAL_ENTRY_OUT)
               {
                  double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                  if(profit < 0) consecutiveLosses++;
                  else if(profit > 0) break;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Dashboard Functions                                              |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   int x = 10;
   int y = 30;
   int step = 25;
   
   ObjectCreate(0, lbl_0, OBJ_LABEL, 0, 0, 0);
   ObjectCreate(0, lbl_1, OBJ_LABEL, 0, 0, 0);
   ObjectCreate(0, lbl_2, OBJ_LABEL, 0, 0, 0);
   ObjectCreate(0, lbl_3, OBJ_LABEL, 0, 0, 0);
   ObjectCreate(0, lbl_4, OBJ_LABEL, 0, 0, 0);
   ObjectCreate(0, lbl_5, OBJ_LABEL, 0, 0, 0);

   string names[6];
   names[0] = lbl_0; names[1] = lbl_1; names[2] = lbl_2;
   names[3] = lbl_3; names[4] = lbl_4; names[5] = lbl_5;

   for(int i=0; i<6; i++)
   {
      ObjectSetInteger(0, names[i], OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, names[i], OBJPROP_YDISTANCE, y + (i * step));
      ObjectSetInteger(0, names[i], OBJPROP_COLOR, clrWhite);
      ObjectSetString(0, names[i], OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, names[i], OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, names[i], OBJPROP_SELECTABLE, false);
   }
}

void UpdateDashboard()
{
   if(!HistorySelect(TimeCurrent() - 86400, TimeCurrent())) return;
   int trades = 0;
   int wins = 0;
   int losses = 0;
   
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         if(HistoryDealSelect(ticket))
         {
            if(HistoryDealGetSymbol(ticket) == _Symbol && HistoryDealGetInteger(ticket, DEAL_MAGIC) == magicNumber)
            {
               long entryType = HistoryDealGetInteger(ticket, DEAL_ENTRY);
               if(entryType == (long)DEAL_ENTRY_OUT)
               {
                  trades++;
                  if(HistoryDealGetDouble(ticket, DEAL_PROFIT) >= 0) wins++;
                  else losses++;
               }
            }
         }
      }
   }
   
   double winRate = 0;
   if(trades > 0) winRate = (double)wins/trades * 100;
   
   ObjectSetString(0, lbl_0, OBJPROP_TEXT, "--- " + botName + " DASHBOARD ---");
   ObjectSetString(0, lbl_1, OBJPROP_TEXT, "Win Rate: " + DoubleToString(winRate, 2) + "%");
   ObjectSetString(0, lbl_2, OBJPROP_TEXT, "Daily Trades: " + IntegerToString(trades));
   ObjectSetString(0, lbl_3, OBJPROP_TEXT, "Wins: " + IntegerToString(wins));
   ObjectSetString(0, lbl_4, OBJPROP_TEXT, "Losses: " + IntegerToString(losses));
   
   string status = "SNIPING ACTIVE";
   color statusColor = clrSpringGreen;
   if(isPaused) { status = "PAUSED (Too Many Losses)"; statusColor = clrOrangeRed; }
   
   ObjectSetString(0, lbl_5, OBJPROP_TEXT, "Status: " + status);
   ObjectSetInteger(0, lbl_5, OBJPROP_COLOR, statusColor);
}
