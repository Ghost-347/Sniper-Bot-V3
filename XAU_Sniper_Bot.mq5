//+------------------------------------------------------------------+
//|                                              XAU_Sniper_Bot.mq5  |
//|                                  Copyright 2024, Quant Engineer  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "5.00"
#property strict

//--- Inputs
input double   Lot_Size        = 0.1;      // Lot Size
input int      SL_Points       = 250;      // SL (Points)
input int      TP_Points       = 750;      // TP (Points)
input int      Max_Losses      = 3;        // Max Consecutive Losses
input int      Swing_Bars      = 15;       // Liquidity Period
input double   Fib_Level       = 0.618;    // Fibonacci Level
input int      ATR_Period      = 14;       // ATR Period
input double   Min_ATR_Points  = 60;       // Min ATR (Points)

//--- Global Variables
bool g_is_paused = false;
long g_magic = 123456;
int  g_h_atr = -1;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_h_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_h_atr != -1) IndicatorRelease(g_h_atr);
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_is_paused) return;

   // 1. Safeguard
   if(HistorySelect(TimeCurrent()-259200, TimeCurrent()))
   {
      int l_cnt = 0;
      int total_deals = HistoryDealsTotal();
      for(int i=total_deals-1; i>=0; i--)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealGetSymbol(ticket) == _Symbol && HistoryDealGetInteger(ticket, DEAL_MAGIC) == g_magic)
         {
            if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            {
               double p = HistoryDealGetDouble(ticket, DEAL_PROFIT);
               if(p < 0) l_cnt++; else if(p > 0) break;
            }
         }
      }
      if(l_cnt >= Max_Losses) { g_is_paused = true; return; }
   }

   // 2. Manage Positions
   int total_p = PositionsTotal();
   for(int i=total_p-1; i>=0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol)
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
                  double nsl = (type == 0) ? op + (d * 0.3) : op - (d * 0.3);
                  bool better = (type == 0 && nsl > sl) || (type == 1 && (nsl < sl || sl <= 0));
                  if(better)
                  {
                     MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req);
                     req.action = TRADE_ACTION_SLTP; req.position = ticket; req.sl = nsl; req.tp = tp;
                     OrderSend(req, res);
                  }
               }
            }
         }
      }
   }

   // 3. Entry
   bool active = false;
   int cur_pos = PositionsTotal();
   for(int i=0; i<cur_pos; i++)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == g_magic) active = true;
   }
   
   if(!active)
   {
      double atr_buf[]; ArraySetAsSeries(atr_buf, true);
      if(CopyBuffer(g_h_atr, 0, 0, 1, atr_buf) > 0 && atr_buf[0] >= Min_ATR_Points * _Point)
      {
         double h[], l[], c[];
         ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
         if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, Swing_Bars+1, h) >= Swing_Bars+1 &&
            CopyLow(_Symbol, PERIOD_CURRENT, 0, Swing_Bars+1, l) >= Swing_Bars+1 &&
            CopyClose(_Symbol, PERIOD_CURRENT, 0, 1, c) >= 1)
         {
            int hi = 1; for(int j=2; j<=Swing_Bars; j++) if(h[j]>h[hi]) hi=j;
            int lo = 1; for(int j=2; j<=Swing_Bars; j++) if(l[j]<l[lo]) lo=j;
            
            double h_f[], l_f[];
            if(CopyHigh(_Symbol, PERIOD_M5, 0, 100, h_f) == 100 && CopyLow(_Symbol, PERIOD_M5, 0, 100, l_f) == 100)
            {
               double mx = h_f[0]; for(int j=1; j<100; j++) if(h_f[j]>mx) mx=h_f[j];
               double mn = l_f[0]; for(int j=1; j<100; j++) if(l_f[j]<mn) mn=l_f[j];
               double fb = mn + (mx - mn) * Fib_Level;
               double fs = mx - (mx - mn) * Fib_Level;

               if(c[0] > l[lo] && l[0] < l[lo]) 
               {
                  if(MathAbs(c[0]-fb) < 150*_Point) SendOrder(0, Lot_Size, c[0]-SL_Points*_Point, c[0]+TP_Points*_Point);
               }
               else if(c[0] < h[hi] && h[0] > h[hi]) 
               {
                  if(MathAbs(c[0]-fs) < 150*_Point) SendOrder(1, Lot_Size, c[0]+SL_Points*_Point, c[0]-TP_Points*_Point);
               }
            }
         }
      }
   }
   Comment("Status: "+(g_is_paused?"PAUSED":"ACTIVE"));
}

//+------------------------------------------------------------------+
//| Send Trade Request                                               |
//+------------------------------------------------------------------+
void SendOrder(int type, double v, double sl, double tp)
{
   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req);
   req.action = TRADE_ACTION_DEAL; req.symbol = _Symbol; req.volume = v;
   req.type = (type == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price = (type == 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   req.sl = sl; req.tp = tp; req.magic = g_magic; req.deviation = 10;
   req.type_filling = ORDER_FILLING_FOK;
   if(!OrderSend(req, res)) { req.type_filling = ORDER_FILLING_IOC; OrderSend(req, res); }
}
