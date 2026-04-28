//+------------------------------------------------------------------+
//|                                              XAU_Sniper_Bot.mq5  |
//|                                  Copyright 2024, Quant Engineer  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "30.00"
#property strict

#include <Trade\Trade.mqh>

input double Lot_Size = 0.1;
input int SL_Points = 250;
input int TP_Points = 750;
input int Max_Losses = 3;
input int Swing_Bars = 15;
input int ATR_Period = 14;
input double Min_ATR = 60;

CTrade trade;
int h_atr = -1;
int h_ma = -1;
bool is_paused = false;

int OnInit() {
   h_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   h_ma = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   trade.SetExpertMagicNumber(123456);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int r) {
   if(h_atr != -1) IndicatorRelease(h_atr);
   if(h_ma != -1) IndicatorRelease(h_ma);
   Comment("");
}

void OnTick() {
   if(is_paused) return;
   
   if(HistorySelect(TimeCurrent()-259200, TimeCurrent())) {
      int l = 0;
      int total_deals = HistoryDealsTotal();
      for(int i=total_deals-1; i>=0; i--) {
         ulong t = HistoryDealGetTicket(i);
         if(HistoryDealGetSymbol(t) == _Symbol && HistoryDealGetInteger(t, DEAL_MAGIC) == 123456) {
            if(HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
               double p = HistoryDealGetDouble(t, DEAL_PROFIT);
               if(p < 0) l++;
               else if(p > 0) break;
            }
         }
      }
      if(l >= Max_Losses) { is_paused = true; return; }
   }
   
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t)) {
         if(PositionGetInteger(POSITION_MAGIC) == 123456 && PositionGetString(POSITION_SYMBOL) == _Symbol) {
            double op = PositionGetDouble(POSITION_PRICE_OPEN);
            double cp = PositionGetDouble(POSITION_PRICE_CURRENT);
            double sl = PositionGetDouble(POSITION_SL);
            double tp = PositionGetDouble(POSITION_TP);
            long   type = PositionGetInteger(POSITION_TYPE);
            if(tp > 0) {
               double d = MathAbs(tp - op);
               if(MathAbs(cp - op) >= d * 0.5) {
                  double nsl = (type == POSITION_TYPE_BUY) ? op + d * 0.3 : op - d * 0.3;
                  bool better = (type == POSITION_TYPE_BUY && nsl > sl) || (type == POSITION_TYPE_SELL && (nsl < sl || sl <= 0));
                  if(better) trade.PositionModify(t, nsl, tp);
               }
            }
         }
      }
   }
   
   bool has = false;
   for(int i=0; i<PositionsTotal(); i++) {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t)) {
         if(PositionGetInteger(POSITION_MAGIC) == 123456 && PositionGetString(POSITION_SYMBOL) == _Symbol) has = true;
      }
   }
   
   if(!has) {
      double ab[]; 
      if(CopyBuffer(h_atr, 0, 0, 1, ab) > 0 && ab[0] >= Min_ATR * _Point) {
         double h[], l[], c[], m[], h4[];
         ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
         if(CopyHigh(_Symbol, 0, 0, Swing_Bars+1, h) >= Swing_Bars+1 && 
            CopyLow(_Symbol, 0, 0, Swing_Bars+1, l) >= Swing_Bars+1 && 
            CopyClose(_Symbol, 0, 0, 1, c) > 0 && 
            CopyBuffer(h_ma, 0, 0, 1, m) > 0 && 
            CopyClose(_Symbol, PERIOD_H4, 0, 1, h4) > 0) {
            
            int hi = 1; for(int j=2; j<=Swing_Bars; j++) if(h[j]>h[hi]) hi=j;
            int lo = 1; for(int j=2; j<=Swing_Bars; j++) if(l[j]<l[lo]) lo=j;
            
            if(c[0] > l[lo] && l[0] < l[lo] && h4[0] > m[0]) trade.Buy(Lot_Size, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), c[0]-SL_Points*_Point, c[0]+TP_Points*_Point);
            else if(c[0] < h[hi] && h[0] > h[hi] && h4[0] < m[0]) trade.Sell(Lot_Size, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), c[0]+SL_Points*_Point, c[0]-TP_Points*_Point);
         }
      }
   }
   Comment("Status: " + (is_paused ? "PAUSED" : "ACTIVE"));
}
