//+------------------------------------------------------------------+
//|                                              XAU_Sniper_Bot.mq5  |
//|                                  Copyright 2024, Quant Engineer  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "3.00"
#property strict

//--- Inputs
input double   Lot_Size        = 0.1;      // Lot Size
input int      SL_Pips         = 250;      // SL (Points)
input int      TP_Pips         = 750;      // TP (Points)
input int      Max_Losses      = 3;        // Max Consecutive Losses
input int      Swing_Bars      = 15;       // Liquidity Swing Period
input double   Fib_Level       = 0.618;    // Fibonacci Level
input int      ATR_Period      = 14;       // ATR Period
input double   Min_ATR         = 60;       // Min ATR
input double   Trig_Perc       = 0.5;      // TP % to secure
input double   Sec_Perc        = 0.3;      // % to lock

//--- Global Variables
int g_consecutive_losses = 0;
bool g_is_paused = false;
long g_magic_number = 123456;
int g_handle_atr = -1;
int g_handle_ma_h4 = -1;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_handle_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   g_handle_ma_h4 = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_is_paused) return;
   
   //--- Safeguard Logic
   if(!HistorySelect(TimeCurrent()-259200, TimeCurrent())) return;
   g_consecutive_losses = 0;
   int total_deals = HistoryDealsTotal();
   for(int i=total_deals-1; i>=0; i--)
   {
      ulong t = HistoryDealGetTicket(i);
      if(HistoryDealGetSymbol(t) == _Symbol && HistoryDealGetInteger(t, DEAL_MAGIC) == g_magic_number)
      {
         if(HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            if(HistoryDealGetDouble(t, DEAL_PROFIT) < 0) g_consecutive_losses++;
            else if(HistoryDealGetDouble(t, DEAL_PROFIT) > 0) break;
         }
      }
   }
   if(g_consecutive_losses >= Max_Losses) { g_is_paused = true; return; }

   //--- Position Management (Profit Trap)
   int total_pos = PositionsTotal();
   for(int i=total_pos-1; i>=0; i--)
   {
      string pos_sym = PositionGetSymbol(i);
      if(pos_sym == _Symbol)
      {
         if(PositionGetInteger(POSITION_MAGIC) == g_magic_number)
         {
            ulong  pos_ticket = PositionGetInteger(POSITION_TICKET);
            double pos_open   = PositionGetDouble(POSITION_PRICE_OPEN);
            double pos_cur    = PositionGetDouble(POSITION_PRICE_CURRENT);
            double pos_sl     = PositionGetDouble(POSITION_SL);
            double pos_tp     = PositionGetDouble(POSITION_TP);
            long   pos_type   = PositionGetInteger(POSITION_TYPE);
            
            if(pos_tp > 0)
            {
               double diff = MathAbs(pos_tp - pos_open);
               double pnl  = MathAbs(pos_cur - pos_open);
               if(pnl >= diff * Trig_Perc)
               {
                  double n_sl = (pos_type == 0) ? pos_open + (diff * Sec_Perc) : pos_open - (diff * Sec_Perc);
                  bool is_better = (pos_type == 0 && n_sl > pos_sl) || (pos_type == 1 && (n_sl < pos_sl || pos_sl <= 0));
                  if(is_better)
                  {
                     MqlTradeRequest req;
                     MqlTradeResult res;
                     ZeroMemory(req);
                     req.action = TRADE_ACTION_SLTP;
                     req.position = pos_ticket;
                     req.symbol = _Symbol;
                     req.sl = n_sl;
                     req.tp = pos_tp;
                     OrderSend(req, res);
                  }
               }
            }
         }
      }
   }

   //--- Sniper Entry Logic
   if(!Position_Exists())
   {
      double atr_buf[];
      ArraySetAsSeries(atr_buf, true);
      if(CopyBuffer(g_handle_atr, 0, 0, 1, atr_buf) <= 0) return;
      if(atr_buf[0] < Min_ATR * _Point) return;
      
      double ma_buf[], cl_buf[];
      ArraySetAsSeries(ma_buf, true); ArraySetAsSeries(cl_buf, true);
      if(CopyBuffer(g_handle_ma_h4, 0, 0, 1, ma_buf) <= 0 || CopyClose(_Symbol, PERIOD_H4, 0, 1, cl_buf) <= 0) return;
      
      double h_buf[], l_buf[], c_buf[];
      ArraySetAsSeries(h_buf, true); ArraySetAsSeries(l_buf, true); ArraySetAsSeries(c_buf, true);
      if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, Swing_Bars+1, h_buf) < Swing_Bars+1) return;
      if(CopyLow(_Symbol, PERIOD_CURRENT, 0, Swing_Bars+1, l_buf) < Swing_Bars+1) return;
      if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 1, c_buf) < 1) return;
      
      int hi_idx = ArrayMaximum(h_buf, 1, Swing_Bars);
      int lo_idx = ArrayMinimum(l_buf, 1, Swing_Bars);
      if(hi_idx < 0 || lo_idx < 0) return;

      double fib_buy = Get_Fibo(PERIOD_M5, true);
      double fib_sell = Get_Fibo(PERIOD_M5, false);

      if(c_buf[0] > l_buf[lo_idx] && l_buf[0] < l_buf[lo_idx] && cl_buf[0] > ma_buf[0])
      {
         if(fib_buy > 0 && MathAbs(c_buf[0] - fib_buy) < 150*_Point) Send_Order(0, Lot_Size, c_buf[0]-SL_Pips*_Point, c_buf[0]+TP_Pips*_Point);
      }
      else if(c_buf[0] < h_buf[hi_idx] && h_buf[0] > h_buf[hi_idx] && cl_buf[0] < ma_buf[0])
      {
         if(fib_sell > 0 && MathAbs(c_buf[0] - fib_sell) < 150*_Point) Send_Order(1, Lot_Size, c_buf[0]+SL_Pips*_Point, c_buf[0]-TP_Pips*_Point);
      }
   }
   Update_Dashboard();
}

//+------------------------------------------------------------------+
//| Check if position exists                                         |
//+------------------------------------------------------------------+
bool Position_Exists()
{
   int total = PositionsTotal();
   for(int i=total-1; i>=0; i--)
   {
      string s = PositionGetSymbol(i);
      if(s == _Symbol && PositionGetInteger(POSITION_MAGIC) == g_magic_number) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci Level                                        |
//+------------------------------------------------------------------+
double Get_Fibo(ENUM_TIMEFRAMES tf, bool is_buy)
{
   double hh[], ll[];
   if(CopyHigh(_Symbol, tf, 0, 100, hh) < 100 || CopyLow(_Symbol, tf, 0, 100, ll) < 100) return 0;
   int hi = ArrayMaximum(hh, 0, 100); int lo = ArrayMinimum(ll, 0, 100);
   if(hi < 0 || lo < 0) return 0;
   double mx = hh[hi]; double mn = ll[lo];
   return is_buy ? mn + (mx-mn)*Fib_Level : mx - (mx-mn)*Fib_Level;
}

//+------------------------------------------------------------------+
//| Send Trade Request                                               |
//+------------------------------------------------------------------+
void Send_Order(int o_type, double o_lot, double o_sl, double o_tp)
{
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = o_lot;
   req.magic  = g_magic_number;
   req.type   = (o_type == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price  = (o_type == 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   req.sl     = o_sl;
   req.tp     = o_tp;
   req.deviation = 10;
   req.type_filling = ORDER_FILLING_IOC;
   OrderSend(req, res);
}

//+------------------------------------------------------------------+
//| Update Dashboard Comment                                         |
//+------------------------------------------------------------------+
void Update_Dashboard()
{
   if(!HistorySelect(TimeCurrent()-86400, TimeCurrent())) return;
   int tr_cnt=0, w_cnt=0;
   int total = HistoryDealsTotal();
   for(int i=total-1; i>=0; i--)
   {
      ulong t = HistoryDealGetTicket(i);
      if(HistoryDealGetSymbol(t) == _Symbol && HistoryDealGetInteger(t, DEAL_MAGIC) == g_magic_number && HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_OUT)
      {
         tr_cnt++; if(HistoryDealGetDouble(t, DEAL_PROFIT) >= 0) w_cnt++;
      }
   }
   double w_rate = (tr_cnt > 0) ? (double)w_cnt/tr_cnt*100 : 0;
   Comment("SNIPER V3.0\nStatus: "+(g_is_paused?"PAUSED":"ACTIVE")+"\nWinRate: "+DoubleToString(w_rate,1)+"%\nWins: "+(string)w_cnt);
}
