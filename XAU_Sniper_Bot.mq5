//+------------------------------------------------------------------+
//|                                              XAU_Sniper_Bot.mq5  |
//|                                  Copyright 2024, Quant Engineer  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "4.00"
#property strict

//--- Includes
#include <Trade\Trade.mqh>

//--- Inputs
input double   InpLotSize        = 0.1;      // Lot Size
input int      InpStopLossPips   = 250;      // SL (Points)
input int      InpTakeProfitPips = 750;      // TP (Points)
input int      InpMaxLosses      = 3;        // Max Consecutive Losses
input int      InpSwingPeriod    = 15;       // Liquidity Period
input double   InpFibLevel       = 0.618;    // Fibonacci Level
input int      InpATRPeriod      = 14;       // ATR Period
input double   InpMinATR         = 60;       // Min ATR (Points)
input double   InpTrigPerc       = 0.5;      // TP % to start secure
input double   InpSecPerc        = 0.3;      // % to lock

//--- Global Variables
CTrade trade;
int g_handle_atr = INVALID_HANDLE;
int g_handle_ma_h4 = INVALID_HANDLE;
bool g_is_paused = false;
long g_magic = 123456;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(g_magic);
   g_handle_atr = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   g_handle_ma_h4 = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   if(g_handle_atr == INVALID_HANDLE || g_handle_ma_h4 == INVALID_HANDLE) return(INIT_FAILED);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(g_handle_atr);
   IndicatorRelease(g_handle_ma_h4);
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_is_paused) return;

   //--- 1. Check Consecutive Losses
   if(HistorySelect(TimeCurrent()-259200, TimeCurrent()))
   {
      int losses = 0;
      int total = HistoryDealsTotal();
      for(int i=total-1; i>=0; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(HistoryDealGetSymbol(t) == _Symbol && HistoryDealGetInteger(t, DEAL_MAGIC) == g_magic)
         {
            if(HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            {
               double p = HistoryDealGetDouble(t, DEAL_PROFIT);
               if(p < 0) losses++;
               else if(p > 0) break;
            }
         }
      }
      if(losses >= InpMaxLosses)
      {
         g_is_paused = true;
         SendNotification("XAU Sniper: Bot Paused.");
         return;
      }
   }

   //--- 2. Manage Positions (Profit Trap)
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
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            if(tp > 0)
            {
               double total_pts = MathAbs(tp - op);
               double cur_pts = MathAbs(cp - op);
               if(cur_pts >= total_pts * InpTrigPerc)
               {
                  double n_sl = (type == POSITION_TYPE_BUY) ? op + (total_pts * InpSecPerc) : op - (total_pts * InpSecPerc);
                  bool better = (type == POSITION_TYPE_BUY && n_sl > sl) || (type == POSITION_TYPE_SELL && (n_sl < sl || sl <= 0));
                  if(better) trade.PositionModify(t, n_sl, tp);
               }
            }
         }
      }
   }

   //--- 3. Sniper Entry
   if(PositionsTotal() == 0)
   {
      double atr[];
      if(CopyBuffer(g_handle_atr, 0, 0, 1, atr) <= 0) return;
      if(atr[0] < InpMinATR * _Point) return;
      
      double ma[], h4c[];
      if(CopyBuffer(g_handle_ma_h4, 0, 0, 1, ma) <= 0 || CopyClose(_Symbol, PERIOD_H4, 0, 1, h4c) <= 0) return;
      
      double hi[], lo[], cl[];
      ArraySetAsSeries(hi, true); ArraySetAsSeries(lo, true); ArraySetAsSeries(cl, true);
      if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, InpSwingPeriod+1, hi) < InpSwingPeriod+1) return;
      if(CopyLow(_Symbol, PERIOD_CURRENT, 0, InpSwingPeriod+1, lo) < InpSwingPeriod+1) return;
      if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 1, cl) < 1) return;
      
      int mHi = ArrayMaximum(hi, 1, InpSwingPeriod);
      int mLo = ArrayMinimum(lo, 1, InpSwingPeriod);
      if(mHi < 0 || mLo < 0) return;

      double f_buy = GetFibo(PERIOD_M5, true);
      double f_sell = GetFibo(PERIOD_M5, false);

      if(cl[0] > lo[mLo] && lo[0] < lo[mLo] && h4c[0] > ma[0])
      {
         if(f_buy > 0 && MathAbs(cl[0] - f_buy) < 150*_Point)
            trade.Buy(InpLotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), cl[0]-InpStopLossPips*_Point, cl[0]+InpTakeProfitPips*_Point);
      }
      else if(cl[0] < hi[mHi] && hi[0] > hi[mHi] && h4c[0] < ma[0])
      {
         if(f_sell > 0 && MathAbs(cl[0] - f_sell) < 150*_Point)
            trade.Sell(InpLotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), cl[0]+InpStopLossPips*_Point, cl[0]-InpTakeProfitPips*_Point);
      }
   }
   
   // Dashboard
   Comment("--- XAU SNIPER V4 ---\nStatus: "+(g_is_paused?"PAUSED":"ACTIVE"));
}

double GetFibo(ENUM_TIMEFRAMES tf, bool buy)
{
   double h[], l[];
   if(CopyHigh(_Symbol, tf, 0, 100, h) < 100 || CopyLow(_Symbol, tf, 0, 100, l) < 100) return 0;
   double mx = h[ArrayMaximum(h, 0, 100)];
   double mn = l[ArrayMinimum(l, 0, 100)];
   return buy ? mn + (mx-mn)*InpFibLevel : mx - (mx-mn)*InpFibLevel;
}
