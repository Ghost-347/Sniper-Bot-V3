//+------------------------------------------------------------------+
//|                                              XAU_Sniper_Bot.mq5  |
//|                                  Copyright 2024, Quant Engineer  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "16.00"
#property strict

//--- Inputs
input double LotSize      = 0.1;
input int    SL_Points    = 250;
input int    TP_Points    = 750;
input int    MaxLosses    = 3;
input int    SwingPeriod  = 15;
input double FibLevel     = 0.618;
input int    ATR_Period   = 14;
input double Min_ATR      = 60;

//--- Globals
int    hATR = -1;
int    hMA  = -1;
bool   paused = false;
long   magic = 123456;

int OnInit() {
   hATR = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   hMA  = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   if(hATR == -1 || hMA == -1) return(1); 
   return(0); 
}

void OnDeinit(const int reason) {
   if(hATR != -1) IndicatorRelease(hATR);
   if(hMA != -1) IndicatorRelease(hMA);
   Comment("");
}

void OnTick() {
   if(paused) return;

   // 1. Loss Protection
   if(HistorySelect(TimeCurrent()-259200, TimeCurrent())) {
      int losses = 0;
      int total_d = HistoryDealsTotal();
      for(int i=total_d-1; i>=0; i--) {
         ulong t = HistoryDealGetTicket(i);
         if(HistoryDealGetSymbol(t) == _Symbol && HistoryDealGetInteger(t, 10) == magic) { 
            if(HistoryDealGetInteger(t, 4) == 1) { 
               if(HistoryDealGetDouble(t, 13) < 0) losses++; 
               else if(HistoryDealGetDouble(t, 13) > 0) break;
            }
         }
      }
      if(losses >= MaxLosses) { paused = true; return; }
   }

   // 2. Trailing Stop
   int total_p = PositionsTotal();
   for(int i=total_p-1; i>=0; i--) {
      string sym = PositionGetSymbol(i);
      if(sym == _Symbol) {
         if(PositionGetInteger(5) == magic) { 
            ulong  ticket = PositionGetInteger(0); 
            double op     = PositionGetDouble(1); 
            double cp     = PositionGetDouble(6); 
            double sl     = PositionGetDouble(3); 
            double tp     = PositionGetDouble(4); 
            long   type   = PositionGetInteger(7); 
            
            if(tp > 0) {
               double d = MathAbs(tp - op);
               if(MathAbs(cp - op) >= d * 0.5) {
                  double nsl = (type == 0) ? op + (d * 0.3) : op - (d * 0.3); 
                  bool better = (type == 0 && nsl > sl) || (type == 1 && (nsl < sl || sl <= 0));
                  if(better) {
                     MqlTradeRequest r; MqlTradeResult res;
                     r.action = 6; 
                     r.position = ticket; r.symbol = _Symbol; r.sl = nsl; r.tp = tp;
                     OrderSend(r, res);
                  }
               }
            }
         }
      }
   }

   // 3. Entry
   bool active = false;
   for(int i=0; i<PositionsTotal(); i++) {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(5) == magic) active = true;
   }
   
   if(!active) {
      double atr_b[]; ArraySetAsSeries(atr_b, true);
      if(CopyBuffer(hATR, 0, 0, 1, atr_b) > 0 && atr_b[0] >= Min_ATR * _Point) {
         double h[], l[], c[], ma_b[], h4c[];
         ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
         if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, SwingPeriod+1, h) >= SwingPeriod+1 &&
            CopyLow(_Symbol, PERIOD_CURRENT, 0, SwingPeriod+1, l) >= SwingPeriod+1 &&
            CopyClose(_Symbol, PERIOD_CURRENT, 0, 1, c) >= 1 &&
            CopyBuffer(hMA, 0, 0, 1, ma_b) > 0 &&
            CopyClose(_Symbol, PERIOD_H4, 0, 1, h4c) > 0) {
            
            int hi = ArrayMaximum(h, 1, SwingPeriod);
            int lo = ArrayMinimum(l, 1, SwingPeriod);
            
            if(hi >= 0 && lo >= 0) {
               double h_f[], l_f[];
               if(CopyHigh(_Symbol, PERIOD_M5, 0, 100, h_f) == 100 && CopyLow(_Symbol, PERIOD_M5, 0, 100, l_f) == 100) {
                  double mx = h_f[0]; for(int j=1; j<100; j++) if(h_f[j]>mx) mx=h_f[j];
                  double mn = l_f[0]; for(int j=1; j<100; j++) if(l_f[j]<mn) mn=l_f[j];
                  double fb = mn + (mx-mn)*FibLevel;
                  double fs = mx - (mx-mn)*FibLevel;

                  if(c[0] > l[lo] && l[0] < l[lo] && h4c[0] > ma_b[0] && MathAbs(c[0]-fb) < 150*_Point) {
                     SendOrder(0, LotSize, c[0]-SL_Points*_Point, c[0]+TP_Points*_Point);
                  }
                  else if(c[0] < h[hi] && h[0] > h[hi] && h4c[0] < ma_b[0] && MathAbs(c[0]-fs) < 150*_Point) {
                     SendOrder(1, LotSize, c[0]+SL_Points*_Point, c[0]-TP_Points*_Point);
                  }
               }
            }
         }
      }
   }
   Comment("Status: "+(paused?"PAUSED":"ACTIVE"));
}

void SendOrder(int type, double v, double sl, double tp) {
   MqlTradeRequest r; MqlTradeResult res;
   ZeroMemory(r);
   r.action = 1; 
   r.symbol = _Symbol; r.volume = v; r.magic = magic;
   r.type = (type == 0) ? 0 : 1; 
   r.price = (type == 0) ? SymbolInfoDouble(_Symbol, 9) : SymbolInfoDouble(_Symbol, 11); 
   r.sl = sl; r.tp = tp; r.deviation = 10;
   r.type_filling = 1; 
   if(!OrderSend(r, res)) { r.type_filling = 2; OrderSend(r, res); } 
}
