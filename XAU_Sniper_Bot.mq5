//+------------------------------------------------------------------+
//|                                              XAU_Sniper_Bot.mq5  |
//|                                  Copyright 2024, Quant Engineer  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "20.00"
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
int    g_h_atr = -1;
int    g_h_ma  = -1;
bool   g_paused = false;
long   g_magic = 123456;

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
      int losses = 0;
      int total = HistoryDealsTotal();
      for(int i=total-1; i>=0; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(HistoryDealGetSymbol(t) == _Symbol && HistoryDealGetInteger(t, DEAL_MAGIC) == g_magic)
         {
            if(HistoryDealGetInteger(t, DEAL_ENTRY) == 1) // 1 = DEAL_ENTRY_OUT
            {
               double p = HistoryDealGetDouble(t, DEAL_PROFIT);
               if(p < 0) losses++; else if(p > 0) break;
            }
         }
      }
      if(losses >= MaxLosses) { g_paused = true; return; }
   }

   // 2. Trailing Stop (Profit Trap)
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(PositionSelectBySymbol(_Symbol))
      {
         if(PositionGetInteger(POSITION_MAGIC) == g_magic)
         {
            ulong  ticket = PositionGetInteger(POSITION_TICKET);
            double op     = PositionGetDouble(POSITION_PRICE_OPEN);
            double cp     = PositionGetDouble(POSITION_PRICE_CURRENT);
            double sl     = PositionGetDouble(POSITION_SL);
            double tp     = PositionGetDouble(POSITION_TP);
            long   type   = PositionGetInteger(POSITION_TYPE);
            
            if(tp > 0)
            {
               double d = MathAbs(tp - op);
               if(MathAbs(cp - op) >= d * 0.5)
               {
                  double nsl = (type == 0) ? op + (d * 0.3) : op - (d * 0.3); // 0=Buy
                  bool better = (type == 0 && nsl > sl) || (type == 1 && (nsl < sl || sl <= 0));
                  if(better)
                  {
                     MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req);
                     req.action = TRADE_ACTION_SLTP; req.position = ticket; req.symbol = _Symbol;
                     req.sl = nsl; req.tp = tp;
                     OrderSend(req, res);
                  }
               }
            }
         }
      }
   }

   // 3. Entry
   bool active = false;
   for(int i=0; i<PositionsTotal(); i++)
   {
      if(PositionSelectBySymbol(_Symbol))
      {
         if(PositionGetInteger(POSITION_MAGIC) == g_magic) active = true;
      }
   }
   
   if(!active)
   {
      double atr_b[]; ArraySetAsSeries(atr_b, true);
      if(CopyBuffer(g_h_atr, 0, 0, 1, atr_b) > 0 && atr_b[0] >= Min_ATR * _Point)
      {
         double h[], l[], c[], ma_b[], h4c[];
         ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
         
         if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, SwingPeriod+1, h) >= SwingPeriod+1 &&
            CopyLow(_Symbol, PERIOD_CURRENT, 0, SwingPeriod+1, l) >= SwingPeriod+1 &&
            CopyClose(_Symbol, PERIOD_CURRENT, 0, 1, c) >= 1 &&
            CopyBuffer(g_h_ma, 0, 0, 1, ma_b) > 0 &&
            CopyClose(_Symbol, PERIOD_H4, 0, 1, h4c) > 0)
         {
            int hi = ArrayMaximum(h, 1, SwingPeriod);
            int lo = ArrayMinimum(l, 1, SwingPeriod);
            
            if(hi >= 0 && lo >= 0)
            {
               double hf[], lf[];
               if(CopyHigh(_Symbol, PERIOD_M5, 0, 100, hf) == 100 && CopyLow(_Symbol, PERIOD_M5, 0, 100, lf) == 100)
               {
                  double mx = hf[0]; for(int j=1; j<100; j++) if(hf[j]>mx) mx=hf[j];
                  double mn = lf[0]; for(int j=1; j<100; j++) if(lf[j]<mn) mn=lf[j];
                  double fb = mn + (mx - mn) * FibLevel;
                  double fs = mx - (mx - mn) * FibLevel;

                  if(c[0] > l[lo] && l[0] < l[lo] && h4c[0] > ma_b[0] && MathAbs(c[0]-fb) < 150*_Point)
                  {
                     SendOrder(0, LotSize, c[0]-SL_Points*_Point, c[0]+TP_Points*_Point);
                  }
                  else if(c[0] < h[hi] && h[0] > h[hi] && h4c[0] < ma_b[0] && MathAbs(c[0]-fs) < 150*_Point)
                  {
                     SendOrder(1, LotSize, c[0]+SL_Points*_Point, c[0]-TP_Points*_Point);
                  }
               }
            }
         }
      }
   }
   Comment("Status: "+(g_paused?"PAUSED":"ACTIVE"));
}

//+------------------------------------------------------------------+
void SendOrder(int type, double v, double sl, double tp)
{
   MqlTradeRequest r; MqlTradeResult res; ZeroMemory(r);
   r.action = TRADE_ACTION_DEAL; r.symbol = _Symbol; r.volume = v; r.magic = g_magic;
   r.type = (type == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   r.price = (type == 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   r.sl = sl; r.tp = tp; r.deviation = 10;
   r.type_filling = ORDER_FILLING_IOC;
   if(!OrderSend(r, res)) { r.type_filling = ORDER_FILLING_FOK; OrderSend(r, res); }
}
