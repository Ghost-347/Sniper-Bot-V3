//+------------------------------------------------------------------+
//|                                              XAU_Sniper_Bot.mq5  |
//|                                  Copyright 2024, Quant Engineer  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Quant Engineer"
#property link      "https://www.mql5.com"
#property version   "2.10"
#property strict

//--- Includes
#include <Trade\Trade.mqh>

//--- Input Parameters
input double   InpLotSize        = 0.1;      // Lot Size
input int      InpStopLossPips   = 250;      // SL in Points
input int      InpTakeProfitPips = 750;      // TP in Points
input int      InpMaxLosses      = 3;        // Max Losses
input bool     InpSendPush       = true;     // Push Notification

input int      InpSwingPeriod    = 15;       
input double   InpFibLevel       = 0.618;    
input ENUM_TIMEFRAMES InpFiboTF  = PERIOD_M5;  
input bool     InpUseTrendFilter = true;     

input int      InpATRPeriod      = 14;       
input double   InpMinATR         = 60;       

input double   InpTriggerLevel   = 0.5;      // TP % to trigger SL move
input double   InpSecureLevel    = 0.3;      // % of TP to secure

//--- Global Variables
CTrade         trade;
int            consecutiveLosses = 0;
bool           isPaused = false;
string         botName = "XAU Sniper Bot";
int            magicNumber = 123456;

int            handleATR = INVALID_HANDLE;
int            handleMA_H4 = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(magicNumber);
   
   handleATR = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   handleMA_H4 = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   if(handleATR == INVALID_HANDLE || handleMA_H4 == INVALID_HANDLE)
   {
      Print("Error: Failed to load indicators.");
      return(INIT_FAILED);
   }
   
   EventSetTimer(1);
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
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(isPaused) return;

   CheckLosses();
   if(consecutiveLosses >= InpMaxLosses)
   {
      isPaused = true;
      if(InpSendPush) SendNotification(botName + " paused on " + _Symbol);
      return;
   }

   ManagePositions();

   if(!PositionExists())
   {
      CheckEntry();
   }
   
   UpdateDash();
}

void OnTimer() { UpdateDash(); }

bool PositionExists()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
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

void CheckEntry()
{
   double atr[];
   if(CopyBuffer(handleATR, 0, 0, 1, atr) <= 0) return;
   if(atr[0] < InpMinATR * _Point) return;

   bool trendOK = true;
   if(InpUseTrendFilter)
   {
      double ma[];
      double cl[];
      if(CopyBuffer(handleMA_H4, 0, 0, 1, ma) > 0 && CopyClose(_Symbol, PERIOD_H4, 0, 1, cl) > 0)
         trendOK = (cl[0] > ma[0]);
   }

   double h[], l[], c[];
   ArraySetAsSeries(h, true);
   ArraySetAsSeries(l, true);
   ArraySetAsSeries(c, true);
   
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, InpSwingPeriod + 1, h) < InpSwingPeriod + 1) return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, InpSwingPeriod + 1, l) < InpSwingPeriod + 1) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 1, c) < 1) return;

   int hiIdx = ArrayMaximum(h, 1, InpSwingPeriod);
   int loIdx = ArrayMinimum(l, 1, InpSwingPeriod);
   if(hiIdx < 0 || loIdx < 0) return;

   double sH = h[hiIdx];
   double sL = l[loIdx];
   double cH = h[0];
   double cL = l[0];
   double cC = c[0];

   double fBuy = GetFib(InpFiboTF, true);
   double fSell = GetFib(InpFiboTF, false);

   if(cL < sL && cC > sL && trendOK)
   {
      if(fBuy > 0 && MathAbs(cC - fBuy) < 150 * _Point)
      {
         double sl = cC - InpStopLossPips * _Point;
         double tp = cC + InpTakeProfitPips * _Point;
         trade.Buy(InpLotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), sl, tp);
      }
   }
   else if(cH > sH && cC < sH && !trendOK)
   {
      if(fSell > 0 && MathAbs(cC - fSell) < 150 * _Point)
      {
         double sl = cC + InpStopLossPips * _Point;
         double tp = cC - InpTakeProfitPips * _Point;
         trade.Sell(InpLotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), sl, tp);
      }
   }
}

double GetFib(ENUM_TIMEFRAMES tf, bool buy)
{
   double hh[], ll[];
   if(CopyHigh(_Symbol, tf, 0, 150, hh) < 150 || CopyLow(_Symbol, tf, 0, 150, ll) < 150) return 0;
   double mx = hh[ArrayMaximum(hh)];
   double mn = ll[ArrayMinimum(ll)];
   if(buy) return mn + (mx - mn) * InpFibLevel;
   return mx - (mx - mn) * InpFibLevel;
}

void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionSelectByTicket(t))
      {
         if(PositionGetInteger(POSITION_MAGIC) == magicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double en = PositionGetDouble(POSITION_PRICE_OPEN);
            double pr = PositionGetDouble(POSITION_PRICE_CURRENT);
            double sl = PositionGetDouble(POSITION_SL);
            double tp = PositionGetDouble(POSITION_TP);
            long type = PositionGetInteger(POSITION_TYPE);
            if(tp <= 0) continue;
            double tP = MathAbs(tp - en);
            double cP = MathAbs(pr - en);
            if(cP >= tP * InpTriggerLevel)
            {
               double nSL = (type == POSITION_TYPE_BUY) ? en + (tP * InpSecureLevel) : en - (tP * InpSecureLevel);
               if((type == POSITION_TYPE_BUY && nSL > sl) || (type == POSITION_TYPE_SELL && (nSL < sl || sl <= 0)))
                  trade.PositionModify(t, nSL, tp);
            }
         }
      }
   }
}

void CheckLosses()
{
   if(!HistorySelect(TimeCurrent() - 259200, TimeCurrent())) return;
   int total = HistoryDealsTotal();
   consecutiveLosses = 0;
   for(int i = total - 1; i >= 0; i--)
   {
      ulong t = HistoryDealGetTicket(i);
      if(HistoryDealGetSymbol(t) == _Symbol && HistoryDealGetInteger(t, DEAL_MAGIC) == magicNumber)
      {
         if(HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            if(HistoryDealGetDouble(t, DEAL_PROFIT) < 0) consecutiveLosses++;
            else if(HistoryDealGetDouble(t, DEAL_PROFIT) > 0) break;
         }
      }
   }
}

void UpdateDash()
{
   if(!HistorySelect(TimeCurrent() - 86400, TimeCurrent())) return;
   int tr = 0, w = 0, l = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong t = HistoryDealGetTicket(i);
      if(HistoryDealGetSymbol(t) == _Symbol && HistoryDealGetInteger(t, DEAL_MAGIC) == magicNumber)
      {
         if(HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            tr++;
            if(HistoryDealGetDouble(t, DEAL_PROFIT) >= 0) w++; else l++;
         }
      }
   }
   double wr = (tr > 0) ? (double)w/tr * 100 : 0;
   string msg = "WinRate: " + DoubleToString(wr, 1) + "% | Wins: " + (string)w + " | Losses: " + (string)l;
   Comment(botName + " - " + (isPaused ? "PAUSED" : "ACTIVE") + "\n" + msg);
}
