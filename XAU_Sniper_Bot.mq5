//+------------------------------------------------------------------+
//|                                              XAU_Sniper_Bot.mq5  |
//|                                  Copyright 2024, Quant Engineer  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "15.00"
#property strict

//--- Inputs
input double InpLotSize = 0.1;      // Lot Size
input int    InpSL      = 250;      // Stop Loss (Points)
input int    InpTP      = 750;      // Take Profit (Points)
input int    InpMaxLoss = 3;        // Max Consecutive Losses
input int    InpSwing   = 15;       // Swing Period
input double InpFib     = 0.618;    // Fib Level (0.618)
input int    InpATR     = 14;       // ATR Period
input double InpMinATR  = 60;       // Min ATR (Points)

//--- Globals
int    hATR = -1;
int    hMA  = -1;
bool   paused = false;
long   magic = 123456;

//+------------------------------------------------------------------+
int OnInit()
{
   hATR = iATR(_Symbol, PERIOD_CURRENT, InpATR);
   hMA  = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   if(hATR == -1 || hMA == -1) return(INIT_FAILED);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hATR != -1) IndicatorRelease(hATR);
   if(hMA != -1) IndicatorRelease(hMA);
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(paused) return;

   // 1. Loss Safeguard
   if(HistorySelect(TimeCurrent()-259200, TimeCurrent()))
   {
      int l = 0;
      int total = HistoryDealsTotal();
      for(int i=total-1; i>=0; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(HistoryDealGetSymbol(t) == _Symbol && HistoryDealGetInteger(t, DEAL_MAGIC) == magic)
         {
            if(HistoryDealGetInteger(t, DEAL_ENTRY) == 1) // 1 = DEAL_ENTRY_OUT
            {
               if(HistoryDealGetDouble(t, DEAL_PROFIT) < 0) l++;
               else if(HistoryDealGetDouble(t, DEAL_PROFIT) > 0) break;
            }
         }
      }
      if(l >= InpMaxLoss) { paused = true; return; }
   }

   // 2. Manage Positions (Profit Trap)
   int total_p = PositionsTotal();
   for(int i=total_p-1; i>=0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol)
      {
         if(PositionGetInteger(POSITION_MAGIC) == magic)
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
                  double nsl = (type == 0) ? op + (d * 0.3) : op - (d * 0.3); // 0 = POSITION_TYPE_BUY
                  bool better = (type == 0 && nsl > sl) || (type == 1 && (nsl < sl || sl <= 0)); // 1 = POSITION_TYPE_SELL
                  if(better)
                  {
                     MqlTradeRequest req; MqlTradeResult res;
                     req.action = 6; // 6 = TRADE_ACTION_SLTP
                     req.position = ticket; req.symbol = _Symbol; req.sl = nsl; req.tp = tp;
                     OrderSend(req, res);
                  }
               }
            }
         }
      }
   }

   // 3. Entry Logic
   bool active = false;
   for(int i=0; i<PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic) active = true;
   }
   
   if(!active)
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
               double mx=0, mn=0;
               double h_f[], l_f[];
               if(CopyHigh(_Symbol, PERIOD_M5, 0, 100, h_f) == 100 && CopyLow(_Symbol, PERIOD_M5, 0, 100, l_f) == 100)
               {
                  mx = h_f[ArrayMaximum(h_f, 0, 100)];
                  mn = l_f[ArrayMinimum(l_f, 0, 100)];
                  double fb = mn + (mx - mn) * InpFib;
                  double fs = mx - (mx - mn) * InpFib;

                  if(c_b[0] > l_b[lo] && l_b[0] < l_b[lo] && h4c_b[0] > ma_b[0])
                  {
                     if(MathAbs(c_b[0]-fb) < 150*_Point) Exec(0, Lot_Size, c_b[0]-InpSL*_Point, c_b[0]+InpTP*_Point);
                  }
                  else if(c_b[0] < h_b[hi] && h_b[0] > h_b[hi] && h4c_b[0] < ma_b[0])
                  {
                     if(MathAbs(c_b[0]-fs) < 150*_Point) Exec(1, Lot_Size, c_b[0]+InpSL*_Point, c_b[0]-InpTP*_Point);
                  }
               }
            }
         }
      }
   }
   Comment("XAU Sniper\nStatus: "+(paused?"PAUSED":"ACTIVE"));
}

//+------------------------------------------------------------------+
void Exec(int type, double v, double sl, double tp)
{
   MqlTradeRequest r; MqlTradeResult res;
   r.action = 1; // 1 = TRADE_ACTION_DEAL
   r.symbol = _Symbol; r.volume = v; r.magic = magic;
   r.type = (type == 0) ? 0 : 1; // 0=Buy, 1=Sell
   r.price = (type == 0) ? SymbolInfoDouble(_Symbol, 9) : SymbolInfoDouble(_Symbol, 11); // 9=Ask, 11=Bid
   r.sl = sl; r.tp = tp; r.deviation = 10;
   r.type_filling = 1; // 1 = ORDER_FILLING_IOC
   if(!OrderSend(r, res)) { r.type_filling = 2; OrderSend(r, res); } // 2 = ORDER_FILLING_FOK
}
