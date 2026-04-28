//+------------------------------------------------------------------+
//|                                              XAU_Sniper_Bot.mq5  |
//|                                  Copyright 2024, Quant Engineer  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "50.00"
#property strict

//--- Includes
#include <Trade\Trade.mqh>

//--- Inputs
input double LotSize      = 0.1;      // Lot Size
input int    SL_Points    = 250;      // Stop Loss (Points)
input int    TP_Points    = 750;      // Take Profit (Points)
input int    MaxLosses    = 3;        // Max Consecutive Losses
input int    SwingPeriod  = 15;       // Liquidity Period
input double FibLevel     = 0.618;    // Fibonacci Level (0.618)
input double MinATR_Pts   = 60;       // Minimum ATR (Points)

//--- Global Variables
CTrade trade;
bool   paused = false;
long   magic  = 123456;
int    h_atr  = -1;
int    h_ma   = -1;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(magic);
   h_atr = iATR(_Symbol, PERIOD_CURRENT, 14);
   h_ma  = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(h_atr != -1) IndicatorRelease(h_atr);
   if(h_ma != -1) IndicatorRelease(h_ma);
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(paused) return;

   // 1. Loss Protection
   if(HistorySelect(TimeCurrent()-259200, TimeCurrent()))
   {
      int losses = 0;
      int total = HistoryDealsTotal();
      for(int i=total-1; i>=0; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(HistoryDealGetSymbol(t) == _Symbol && HistoryDealGetInteger(t, DEAL_MAGIC) == magic)
         {
            if(HistoryDealGetInteger(t, DEAL_ENTRY) == 1) // DEAL_ENTRY_OUT
            {
               if(HistoryDealGetDouble(t, DEAL_PROFIT) < 0) losses++;
               else if(HistoryDealGetDouble(t, DEAL_PROFIT) > 0) break;
            }
         }
      }
      if(losses >= MaxLosses) { paused = true; return; }
   }

   // 2. Trailing Stop (Profit Trap)
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
         {
            double op = PositionGetDouble(POSITION_PRICE_OPEN);
            double cp = PositionGetDouble(POSITION_PRICE_CURRENT);
            double sl = PositionGetDouble(POSITION_SL);
            double tp = PositionGetDouble(POSITION_TP);
            int type = (int)PositionGetInteger(POSITION_TYPE);
            
            if(tp > 0)
            {
               double d = MathAbs(tp - op);
               if(MathAbs(cp - op) >= d * 0.5)
               {
                  double nsl = (type == 0) ? op + (d * 0.3) : op - (d * 0.3);
                  bool better = (type == 0 && nsl > sl) || (type == 1 && (nsl < sl || sl <= 0));
                  if(better) trade.PositionModify(ticket, nsl, tp);
               }
            }
         }
      }
   }

   // 3. Entry
   bool active = false;
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic) active = true;
      }
   }
   
   if(!active)
   {
      double h[], l[], c[], atr_b[], ma_b[], h4c[];
      ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
      
      if(CopyHigh(_Symbol, _Period, 0, SwingPeriod+1, h) >= SwingPeriod+1 &&
         CopyLow(_Symbol, _Period, 0, SwingPeriod+1, l) >= SwingPeriod+1 &&
         CopyClose(_Symbol, _Period, 0, 1, c) >= 1 &&
         CopyBuffer(h_atr, 0, 0, 1, atr_b) > 0 &&
         CopyBuffer(h_ma, 0, 0, 1, ma_b) > 0 &&
         CopyClose(_Symbol, PERIOD_H4, 0, 1, h4c) > 0)
      {
         if(atr_b[0] < MinATR_Pts * _Point) return;

         // Manual High/Low loop to avoid ArrayMaximum/Minimum build issues
         double sHigh = h[1]; double sLow = l[1];
         for(int j=2; j<=SwingPeriod; j++) {
            if(h[j] > sHigh) sHigh = h[j];
            if(l[j] < sLow) sLow = l[j];
         }
         
         double hf[], lf[];
         if(CopyHigh(_Symbol, PERIOD_M5, 0, 100, hf) == 100 && CopyLow(_Symbol, PERIOD_M5, 0, 100, lf) == 100)
         {
            double mx = hf[0]; double mn = lf[0];
            for(int j=1; j<100; j++) {
               if(hf[j] > mx) mx = hf[j];
               if(lf[j] < mn) mn = lf[j];
            }
            double fb = mn + (mx - mn) * FibLevel;
            double fs = mx - (mx - mn) * FibLevel;

            if(c[0] > sLow && l[0] < sLow && h4c[0] > ma_b[0]) // Sweep Buy
            {
               if(MathAbs(c[0]-fb) < 150*_Point)
                  trade.Buy(LotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), c[0]-SL_Points*_Point, c[0]+TP_Points*_Point);
            }
            else if(c[0] < sHigh && h[0] > sHigh && h4c[0] < ma_b[0]) // Sweep Sell
            {
               if(MathAbs(c[0]-fs) < 150*_Point)
                  trade.Sell(LotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), c[0]+SL_Points*_Point, c[0]-TP_Points*_Point);
            }
         }
      }
   }
   Comment("XAU Sniper: " + (paused ? "PAUSED" : "ACTIVE"));
}
