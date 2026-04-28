//+------------------------------------------------------------------+
//|                                              XAU_Sniper_Bot.mq5  |
//|                                  Copyright 2024, Quant Engineer  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.mql5.com"
#property version   "11.00"
#property strict

//--- Includes
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input Parameters
input double LotSize      = 0.1;      // Fixed Lot Size
input int    SL_Points    = 250;      // Stop Loss (Points)
input int    TP_Points    = 750;      // Take Profit (Points)
input int    MaxLosses    = 3;        // Max Consecutive Losses
input int    SwingPeriod  = 15;       // Liquidity Swing Period
input double FibLevel     = 0.618;    // Fibonacci Level
input int    ATR_Period   = 14;       // ATR Period
input double Min_ATR      = 60;       // Minimum ATR (Points)

//--- Global Variables
CTrade         trade;
CPositionInfo  pos;
int            hATR = INVALID_HANDLE;
int            hMA  = INVALID_HANDLE;
bool           paused = false;
long           magic = 123456;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(magic);
   hATR = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   hMA  = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   if(hATR == INVALID_HANDLE || hMA == INVALID_HANDLE) return(INIT_FAILED);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hATR);
   IndicatorRelease(hMA);
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(paused) return;

   // 1. Safeguard Check (Consecutive Losses)
   if(HistorySelect(TimeCurrent()-259200, TimeCurrent()))
   {
      int l_cnt = 0;
      int total = HistoryDealsTotal();
      for(int i=total-1; i>=0; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(HistoryDealGetSymbol(t) == _Symbol && HistoryDealGetInteger(t, DEAL_MAGIC) == magic)
         {
            if(HistoryDealGetInteger(t, DEAL_ENTRY) == (long)DEAL_ENTRY_OUT)
            {
               double p = HistoryDealGetDouble(t, DEAL_PROFIT);
               if(p < 0) l_cnt++;
               else if(p > 0) break;
            }
         }
      }
      if(l_cnt >= MaxLosses)
      {
         paused = true;
         SendNotification("XAU Sniper: Bot Paused due to losses.");
         return;
      }
   }

   // 2. Manage Positions (Profit Trap)
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(pos.SelectByIndex(i) && pos.Symbol() == _Symbol && pos.Magic() == magic)
      {
         double op = pos.PriceOpen();
         double cp = pos.PriceCurrent();
         double sl = pos.StopLoss();
         double tp = pos.TakeProfit();
         
         if(tp > 0)
         {
            double d = MathAbs(tp - op);
            if(MathAbs(cp - op) >= d * 0.5)
            {
               double nsl = (pos.PositionType() == POSITION_TYPE_BUY) ? op + (d * 0.3) : op - (d * 0.3);
               bool better = (pos.PositionType() == POSITION_TYPE_BUY && nsl > sl) || 
                            (pos.PositionType() == POSITION_TYPE_SELL && (nsl < sl || sl <= 0));
               if(better) trade.PositionModify(pos.Ticket(), nsl, tp);
            }
         }
      }
   }

   // 3. Sniper Entry Check
   bool has_pos = false;
   for(int i=0; i<PositionsTotal(); i++)
   {
      if(pos.SelectByIndex(i) && pos.Symbol() == _Symbol && pos.Magic() == magic) has_pos = true;
   }
   
   if(!has_pos)
   {
      double atr[]; ArraySetAsSeries(atr, true);
      if(CopyBuffer(hATR, 0, 0, 1, atr) > 0 && atr[0] >= Min_ATR * _Point)
      {
         double h[], l[], c[], ma[], h4c[];
         ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
         
         if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, SwingPeriod+1, h) >= SwingPeriod+1 &&
            CopyLow(_Symbol, PERIOD_CURRENT, 0, SwingPeriod+1, l) >= SwingPeriod+1 &&
            CopyClose(_Symbol, PERIOD_CURRENT, 0, 1, c) >= 1 &&
            CopyBuffer(hMA, 0, 0, 1, ma) > 0 &&
            CopyClose(_Symbol, PERIOD_H4, 0, 1, h4c) > 0)
         {
            int hi = ArrayMaximum(h, 1, SwingPeriod);
            int lo = ArrayMinimum(l, 1, SwingPeriod);
            
            if(hi >= 0 && lo >= 0)
            {
               double f_buy = GetFibLevel(true);
               double f_sell = GetFibLevel(false);
               
               if(c[0] > l[lo] && l[0] < l[lo] && h4c[0] > ma[0])
               {
                  if(f_buy > 0 && MathAbs(c[0]-f_buy) < 150*_Point)
                     trade.Buy(LotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), c[0]-SL_Points*_Point, c[0]+TP_Points*_Point);
               }
               else if(c[0] < h[hi] && h[0] > h[hi] && h4c[0] < ma[0])
               {
                  if(f_sell > 0 && MathAbs(c[0]-f_sell) < 150*_Point)
                     trade.Sell(LotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), c[0]+SL_Points*_Point, c[0]-TP_Points*_Point);
               }
            }
         }
      }
   }
   
   Comment("--- XAU Sniper Bot ---\nStatus: "+(paused?"PAUSED":"ACTIVE"));
}

//+------------------------------------------------------------------+
double GetFibLevel(bool buy)
{
   double h[], l[];
   if(CopyHigh(_Symbol, PERIOD_M5, 0, 100, h) < 100 || CopyLow(_Symbol, PERIOD_M5, 0, 100, l) < 100) return 0;
   double mx = h[ArrayMaximum(h)];
   double mn = l[ArrayMinimum(l)];
   return buy ? mn + (mx - mn) * FibLevel : mx - (mx - mn) * FibLevel;
}
