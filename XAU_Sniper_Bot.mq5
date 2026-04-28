//+------------------------------------------------------------------+
//|                                              XAU_Sniper_Bot.mq5  |
//|                                  Copyright 2024, Quant Engineer  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "8.00"
#property strict

//--- Risk Inputs
input double   LotSize         = 0.1;      // Lot Size
input int      SL_Points       = 250;      // SL (Points)
input int      TP_Points       = 750;      // TP (Points)
input int      MaxLosses       = 3;        // Consecutive Losses

//--- Strategy Inputs
input int      SwingPeriod     = 15;       // Liquidity Period
input double   FibLevel        = 0.618;    // Fibonacci Level
input int      ATR_Period      = 14;       // ATR Period
input double   Min_ATR         = 60;       // Min ATR (Points)

//--- Global Variables
bool g_paused = false;
long g_magic  = 123456;
int  g_h_atr  = -1;
int  g_h_ma   = -1;

//+------------------------------------------------------------------+
int OnInit()
{
   g_h_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   g_h_ma  = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   if(g_h_atr == -1 || g_h_ma == -1) return(INIT_FAILED);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_h_atr != -1) IndicatorRelease(g_h_atr);
   if(g_h_ma != -1) IndicatorRelease(g_h_ma);
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(g_paused) return;

   // 1. Loss Protection
   if(HistorySelect(TimeCurrent()-259200, TimeCurrent()))
   {
      int l_cnt = 0;
      for(int i=HistoryDealsTotal()-1; i>=0; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(HistoryDealGetSymbol(t) == _Symbol && HistoryDealGetInteger(t, DEAL_MAGIC) == g_magic)
         {
            if(HistoryDealGetInteger(t, DEAL_ENTRY) == 1) // DEAL_ENTRY_OUT = 1
            {
               if(HistoryDealGetDouble(t, DEAL_PROFIT) < 0) l_cnt++; 
               else if(HistoryDealGetDouble(t, DEAL_PROFIT) > 0) break;
            }
         }
      }
      if(l_cnt >= MaxLosses) { g_paused = true; return; }
   }

   // 2. Trailing Stop (Profit Trap)
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(PositionSelectByIndices(i))
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
                  double nsl = (type == 0) ? op + (d * 0.3) : op - (d * 0.3);
                  bool better = (type == 0 && nsl > sl) || (type == 1 && (nsl < sl || sl <= 0));
                  if(better) ModifySL(PositionGetInteger(POSITION_TICKET), nsl, tp);
               }
            }
         }
      }
   }

   // 3. Sniper Entry
   bool has_pos = false;
   for(int i=0; i<PositionsTotal(); i++) {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == g_magic) has_pos = true;
   }

   if(!has_pos)
   {
      double atr_b[]; ArraySetAsSeries(atr_b, true);
      if(CopyBuffer(g_h_atr, 0, 0, 1, atr_b) <= 0) return;
      if(atr_b[0] < Min_ATR * _Point) return;
      
      double ma_b[], h4c[]; 
      if(CopyBuffer(g_h_ma, 0, 0, 1, ma_b) <= 0 || CopyClose(_Symbol, PERIOD_H4, 0, 1, h4c) <= 0) return;
      
      double hi[], lo[], cl[];
      ArraySetAsSeries(hi, true); ArraySetAsSeries(lo, true); ArraySetAsSeries(cl, true);
      if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, SwingPeriod+1, hi) < SwingPeriod+1) return;
      if(CopyLow(_Symbol, PERIOD_CURRENT, 0, SwingPeriod+1, lo) < SwingPeriod+1) return;
      if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 1, cl) < 1) return;
      
      int h_idx = 1; for(int j=2; j<=SwingPeriod; j++) if(hi[j]>hi[h_idx]) h_idx=j;
      int l_idx = 1; for(int j=2; j<=SwingPeriod; j++) if(lo[j]<lo[l_idx]) l_idx=j;

      double f_buy = Calc_Fib(PERIOD_M5, true);
      double f_sell = Calc_Fib(PERIOD_M5, false);

      if(cl[0] > lo[l_idx] && lo[0] < lo[l_idx] && h4c[0] > ma_b[0])
      {
         if(f_buy > 0 && MathAbs(cl[0] - f_buy) < 150*_Point)
            Exec(0, cl[0]-SL_Points*_Point, cl[0]+TP_Points*_Point);
      }
      else if(cl[0] < hi[h_idx] && hi[0] > hi[h_idx] && h4c[0] < ma_b[0])
      {
         if(f_sell > 0 && MathAbs(cl[0] - f_sell) < 150*_Point)
            Exec(1, cl[0]+SL_Points*_Point, cl[0]-TP_Points*_Point);
      }
   }
   Comment("XAU Sniper V8.0\nStatus: "+(g_paused?"PAUSED":"ACTIVE"));
}

// Helper: Selection for older MT5
bool PositionSelectByIndices(int index) {
   string sym = PositionGetSymbol(index);
   return (sym != "");
}

// Helper: Fib calc
double Calc_Fib(ENUM_TIMEFRAMES tf, bool buy) {
   double h[], l[];
   if(CopyHigh(_Symbol, tf, 0, 100, h) < 100 || CopyLow(_Symbol, tf, 0, 100, l) < 100) return 0;
   double mx = h[0]; double mn = l[0];
   for(int j=1; j<100; j++) { if(h[j]>mx) mx=h[j]; if(l[j]<mn) mn=l[j]; }
   return buy ? mn + (mx-mn)*FibLevel : mx - (mx-mn)*FibLevel;
}

// Helper: Modify SL
void ModifySL(ulong ticket, double sl, double tp) {
   MqlTradeRequest r; MqlTradeResult res; ZeroMemory(r);
   r.action = 6; // TRADE_ACTION_SLTP = 6
   r.position = ticket; r.symbol = _Symbol; r.sl = sl; r.tp = tp;
   OrderSend(r, res);
}

// Helper: Execute Trade
void Exec(int type, double sl, double tp) {
   MqlTradeRequest r; MqlTradeResult res; ZeroMemory(r);
   r.action = 1; // TRADE_ACTION_DEAL = 1
   r.symbol = _Symbol; r.volume = LotSize; r.magic = g_magic;
   r.type = (type == 0) ? 0 : 1; // 0=Buy, 1=Sell
   r.price = (type == 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   r.sl = sl; r.tp = tp; r.deviation = 10;
   r.type_filling = 1; // ORDER_FILLING_IOC = 1
   if(!OrderSend(r, res)) { r.type_filling = 2; OrderSend(r, res); } // ORDER_FILLING_FOK = 2
}
