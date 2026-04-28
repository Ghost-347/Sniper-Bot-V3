//+------------------------------------------------------------------+
//|                                              XAU_Sniper_Bot.mq5  |
//|                                  Copyright 2024, Quant Engineer  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "60.00"
#property strict

#include <Trade\Trade.mqh>

input double Lot_Size = 0.1;      // Lot Size
input int    SL_Pts   = 250;      // SL (Points)
input int    TP_Pts   = 750;      // TP (Points)
input int    Max_L    = 3;        // Max Consecutive Losses
input int    Swing_P  = 15;       // Liquidity Swing Period

CTrade trade;
int    h_atr = -1;
int    h_ma  = -1;
bool   is_p  = false;
long   magic = 123456;

int OnInit() {
   trade.SetExpertMagicNumber(magic);
   h_atr = iATR(_Symbol, PERIOD_CURRENT, 14);
   h_ma  = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   return(0);
}

void OnDeinit(const int r) {
   if(h_atr != -1) IndicatorRelease(h_atr);
   if(h_ma != -1) IndicatorRelease(h_ma);
   Comment("");
}

void OnTick() {
   if(is_p) return;

   // 1. Safeguard
   if(HistorySelect(TimeCurrent()-259200, TimeCurrent())) {
      int l = 0;
      int total_deals = HistoryDealsTotal();
      for(int i=total_deals-1; i>=0; i--) {
         ulong t = HistoryDealGetTicket(i);
         if(HistoryDealGetSymbol(t) == _Symbol && HistoryDealGetInteger(t, DEAL_MAGIC) == magic) {
            if(HistoryDealGetInteger(t, DEAL_ENTRY) == 1) { // 1 = OUT
               if(HistoryDealGetDouble(t, DEAL_PROFIT) < 0) l++;
               else if(HistoryDealGetDouble(t, DEAL_PROFIT) > 0) break;
            }
         }
      }
      if(l >= Max_L) { is_p = true; return; }
   }

   // 2. Profit Trap
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionGetSymbol(i) == _Symbol) {
         if(PositionGetInteger(POSITION_MAGIC) == magic) {
            ulong  t = PositionGetInteger(POSITION_TICKET);
            double o = PositionGetDouble(POSITION_PRICE_OPEN);
            double c = PositionGetDouble(POSITION_PRICE_CURRENT);
            double s = PositionGetDouble(POSITION_SL);
            double p = PositionGetDouble(POSITION_TP);
            int    y = (int)PositionGetInteger(POSITION_TYPE);
            if(p > 0) {
               double dist = MathAbs(p - o);
               if(MathAbs(c - o) >= dist * 0.5) {
                  double nsl = (y == 0) ? o + (dist * 0.3) : o - (dist * 0.3);
                  if((y == 0 && nsl > s) || (y == 1 && (nsl < s || s <= 0))) trade.PositionModify(t, nsl, p);
               }
            }
         }
      }
   }

   // 3. Entry
   bool active = false;
   for(int i=0; i<PositionsTotal(); i++) {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic) active = true;
   }
   
   if(!active) {
      double a_b[]; ArraySetAsSeries(a_b, true);
      if(CopyBuffer(h_atr, 0, 0, 1, a_b) > 0 && a_b[0] >= 60 * _Point) {
         double h[], l[], cl[], ma[], h4[];
         ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(cl, true);
         if(CopyHigh(_Symbol, 0, 0, Swing_P+1, h) >= Swing_P+1 && CopyLow(_Symbol, 0, 0, Swing_P+1, l) >= Swing_P+1 && CopyClose(_Symbol, 0, 0, 1, cl) > 0) {
            if(CopyBuffer(h_ma, 0, 0, 1, ma) > 0 && CopyClose(_Symbol, PERIOD_H4, 0, 1, h4) > 0) {
               
               double sHi = h[1]; double sLo = l[1];
               for(int j=2; j<=Swing_P; j++) {
                  if(h[j] > sHi) sHi = h[j];
                  if(l[j] < sLo) sLo = l[j];
               }

               if(cl[0] > sLo && l[0] < sLo && h4[0] > ma[0]) {
                  trade.Buy(Lot_Size, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), cl[0]-SL_Pts*_Point, cl[0]+TP_Pts*_Point);
               }
               else if(cl[0] < sHi && h[0] > sHi && h4[0] < ma[0]) {
                  trade.Sell(Lot_Size, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), cl[0]+SL_Pts*_Point, cl[0]-TP_Pts*_Point);
               }
            }
         }
      }
   }
   Comment("XAU Sniper: " + (is_p ? "PAUSED" : "ACTIVE"));
}
