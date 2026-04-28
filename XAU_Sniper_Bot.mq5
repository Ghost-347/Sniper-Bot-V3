//+------------------------------------------------------------------+
//|                                              XAU_Sniper_Bot.mq5  |
//|                                  Copyright 2024, Quant Engineer  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "7.00"
#property strict

//--- Includes
#include <Trade\Trade.mqh>

//--- Input Parameters (No 'group' to support older MT5)
input double   LotSize         = 0.1;      // Lot Size
input int      SL_Points       = 250;      // Stop Loss (Points)
input int      TP_Points       = 750;      // Take Profit (Points)
input int      MaxLosses       = 3;        // Max Consecutive Losses
input int      SwingPeriod     = 15;       // Liquidity Period
input double   FibLevel        = 0.618;    // Fibonacci Level
input int      ATR_Period      = 14;       // ATR Period
input double   Min_ATR         = 60;       // Minimum ATR (Points)

//--- Global Variables
CTrade trade;
bool g_paused = false;
long g_magic = 123456;
int  g_h_atr = INVALID_HANDLE;
int  g_h_ma  = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(g_magic);
   g_h_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   g_h_ma  = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   if(g_h_atr == INVALID_HANDLE || g_h_ma == INVALID_HANDLE) return(INIT_FAILED);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_h_atr != INVALID_HANDLE) IndicatorRelease(g_h_atr);
   if(g_h_ma != INVALID_HANDLE) IndicatorRelease(g_h_ma);
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(g_paused) return;

   // 1. Safeguard: Consecutive Losses
   if(HistorySelect(TimeCurrent()-259200, TimeCurrent()))
   {
      int l_cnt = 0;
      int total_d = HistoryDealsTotal();
      for(int i=total_d-1; i>=0; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(HistoryDealGetSymbol(t) == _Symbol && HistoryDealGetInteger(t, DEAL_MAGIC) == g_magic)
         {
            if(HistoryDealGetInteger(t, DEAL_ENTRY) == (long)DEAL_ENTRY_OUT)
            {
               double prf = HistoryDealGetDouble(t, DEAL_PROFIT);
               if(prf < 0) l_cnt++; else if(prf > 0) break;
            }
         }
      }
      if(l_cnt >= MaxLosses) { g_paused = true; return; }
   }

   // 2. Profit Trap Logic
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == g_magic)
         {
            double op = PositionGetDouble(POSITION_PRICE_OPEN);
            double cp = PositionGetDouble(POSITION_PRICE_CURRENT);
            double sl = PositionGetDouble(POSITION_SL);
            double tp = PositionGetDouble(POSITION_TP);
            long type = PositionGetInteger(POSITION_TYPE);
            
            if(tp > 0)
            {
               double d = MathAbs(tp - op);
               if(MathAbs(cp - op) >= d * 0.5)
               {
                  double nsl = (type == (long)POSITION_TYPE_BUY) ? op + (d * 0.3) : op - (d * 0.3);
                  bool better = (type == (long)POSITION_TYPE_BUY && nsl > sl) || (type == (long)POSITION_TYPE_SELL && (nsl < sl || sl <= 0));
                  if(better) trade.PositionModify(t, nsl, tp);
               }
            }
         }
      }
   }

   // 3. Sniper Entry
   if(!MyPositionExists())
   {
      double atr_b[]; ArraySetAsSeries(atr_b, true);
      if(CopyBuffer(g_h_atr, 0, 0, 1, atr_b) <= 0) return;
      if(atr_b[0] < Min_ATR * _Point) return;
      
      double ma_b[], h4_c[];
      if(CopyBuffer(g_h_ma, 0, 0, 1, ma_b) <= 0 || CopyClose(_Symbol, PERIOD_H4, 0, 1, h4_c) <= 0) return;
      
      double h_b[], l_b[], c_b[];
      ArraySetAsSeries(h_b, true); ArraySetAsSeries(l_b, true); ArraySetAsSeries(c_b, true);
      if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, SwingPeriod+1, h_b) < SwingPeriod+1) return;
      if(CopyLow(_Symbol, PERIOD_CURRENT, 0, SwingPeriod+1, l_b) < SwingPeriod+1) return;
      if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 1, c_b) < 1) return;
      
      int h_idx = ArrayMaximum(h_b, 1, SwingPeriod);
      int l_idx = ArrayMinimum(l_b, 1, SwingPeriod);
      if(h_idx < 0 || l_idx < 0) return;

      double f_b = GetMyFib(PERIOD_M5, true);
      double f_s = GetMyFib(PERIOD_M5, false);

      if(c_b[0] > l_b[l_idx] && l_b[0] < l_b[l_idx] && h4_c[0] > ma_b[0])
      {
         if(f_b > 0 && MathAbs(c_b[0] - f_b) < 150*_Point)
            trade.Buy(LotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), c_b[0]-SL_Points*_Point, c_b[0]+TP_Points*_Point);
      }
      else if(c_b[0] < h_b[h_idx] && h_b[0] > h_b[h_idx] && h4_c[0] < ma_b[0])
      {
         if(f_s > 0 && MathAbs(c_b[0] - f_s) < 150*_Point)
            trade.Sell(LotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), c_b[0]+SL_Points*_Point, c_b[0]-TP_Points*_Point);
      }
   }
   Comment("XAU Sniper V7\nStatus: "+(g_paused?"PAUSED":"ACTIVE"));
}

//+------------------------------------------------------------------+
bool MyPositionExists()
{
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == g_magic) return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
double GetMyFib(ENUM_TIMEFRAMES tf, bool buy)
{
   double h[], l[];
   if(CopyHigh(_Symbol, tf, 0, 100, h) < 100 || CopyLow(_Symbol, tf, 0, 100, l) < 100) return 0;
   double mx = h[ArrayMaximum(h, 0, 100)];
   double mn = l[ArrayMinimum(l, 0, 100)];
   return buy ? mn + (mx-mn)*FibLevel : mx - (mx-mn)*FibLevel;
}
