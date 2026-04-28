//+------------------------------------------------------------------+
//|                                              XAU_Sniper_Bot.mq5  |
//|                                  Copyright 2024, Quant Engineer  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "12.00"
#property strict

//--- Includes
#include <Trade\Trade.mqh>

//--- Input Parameters
input double InpLotSize = 0.1;      
input int    InpSL      = 250;      
input int    InpTP      = 750;      
input int    InpMaxLoss = 3;        
input int    InpSwing   = 15;       
input double InpFib     = 0.618;    
input int    InpATR     = 14;       
input double InpMinATR  = 60;       

//--- Globals
CTrade trade;
int    hATR = -1;
int    hMA  = -1;
bool   paused = false;
long   magic = 123456;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(magic);
   hATR = iATR(_Symbol, PERIOD_CURRENT, InpATR);
   hMA  = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   if(hATR == INVALID_HANDLE || hMA == INVALID_HANDLE) return(INIT_FAILED);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hMA != INVALID_HANDLE) IndicatorRelease(hMA);
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(paused) return;

   // 1. Safeguard
   if(HistorySelect(TimeCurrent()-259200, TimeCurrent()))
   {
      int l = 0;
      for(int i=HistoryDealsTotal()-1; i>=0; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(HistoryDealGetSymbol(t) == _Symbol && HistoryDealGetInteger(t, DEAL_MAGIC) == magic)
         {
            if(HistoryDealGetInteger(t, DEAL_ENTRY) == (long)DEAL_ENTRY_OUT)
            {
               if(HistoryDealGetDouble(t, DEAL_PROFIT) < 0) l++;
               else if(HistoryDealGetDouble(t, DEAL_PROFIT) > 0) break;
            }
         }
      }
      if(l >= InpMaxLoss) { paused = true; return; }
   }

   // 2. Profit Trap
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionSelectByTicket(t))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
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
                  bool better = (type == (long)POSITION_TYPE_BUY && nsl > sl) || 
                                (type == (long)POSITION_TYPE_SELL && (nsl < sl || sl <= 0));
                  if(better) trade.PositionModify(t, nsl, tp);
               }
            }
         }
      }
   }

   // 3. Entry
   bool has = false;
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionSelectByTicket(t))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic) has = true;
      }
   }
   
   if(!has)
   {
      double atr_b[]; ArraySetAsSeries(atr_b, true);
      if(CopyBuffer(hATR, 0, 0, 1, atr_b) > 0 && atr_b[0] >= InpMinATR * _Point)
      {
         double h_b[], l_b[], c_b[], ma_b[], h4c_b[];
         ArraySetAsSeries(h_b, true); ArraySetAsSeries(l_b, true); ArraySetAsSeries(c_b, true);
         
         if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, InpSwing+1, h_b) >= InpSwing+1 &&
            CopyLow(_Symbol, PERIOD_CURRENT, 0, InpSwing+1, l_b) >= InpSwing+1 &&
            CopyClose(_Symbol, PERIOD_CURRENT, 0, 1, c_b) >= 1 &&
            CopyBuffer(hMA, 0, 0, 1, ma_b) > 0 &&
            CopyClose(_Symbol, PERIOD_H4, 0, 1, h4c_b) > 0)
         {
            int hi = ArrayMaximum(h_b, 1, InpSwing);
            int lo = ArrayMinimum(l_b, 1, InpSwing);
            
            if(hi >= 0 && lo >= 0)
            {
               double f_b = GetF(true);
               double f_s = GetF(false);
               
               if(c_b[0] > l_b[lo] && l_b[0] < l_b[lo] && h4c_b[0] > ma_b[0])
               {
                  if(f_b > 0 && MathAbs(c_b[0]-f_b) < 150*_Point)
                     trade.Buy(InpLotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), c_b[0]-InpSL*_Point, c_b[0]+InpTP*_Point);
               }
               else if(c_b[0] < h_b[hi] && h_b[0] > h_b[hi] && h4c_b[0] < ma_b[0])
               {
                  if(f_s > 0 && MathAbs(c_b[0]-f_s) < 150*_Point)
                     trade.Sell(InpLotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), c_b[0]+InpSL*_Point, c_b[0]-InpTP*_Point);
               }
            }
         }
      }
   }
   Comment("XAU Sniper\nStatus: "+(paused?"PAUSED":"ACTIVE"));
}

//+------------------------------------------------------------------+
double GetF(bool buy)
{
   double h[], l[];
   if(CopyHigh(_Symbol, PERIOD_M5, 0, 100, h) < 100 || CopyLow(_Symbol, PERIOD_M5, 0, 100, l) < 100) return 0;
   int hi = ArrayMaximum(h, 0, 100);
   int lo = ArrayMinimum(l, 0, 100);
   if(hi < 0 || lo < 0) return 0;
   double mx = h[hi];
   double mn = l[lo];
   return buy ? mn + (mx - mn) * InpFib : mx - (mx - mn) * InpFib;
}
