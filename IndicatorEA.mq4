#property strict
#property copyright "EA created from indicator"

extern double Lots = 0.10;
extern int    Slippage = 3;
extern int    StopLossPips = 30;
extern int    TakeProfitPips = 60;

extern int    MagicNumber = 20261114;
extern bool   OneTradeAtATime = true;

bool HasOpenPosition()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == MagicNumber &&
            OrderSymbol() == Symbol())
            return true;
      }
   }
   return false;
}

int OnInit()
{
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(OneTradeAtATime && HasOpenPosition())
      return;

   // TODO: Replace these with your indicator’s buy/sell conditions
   bool buySignal  = false;
   bool sellSignal = false;

   // Example placeholders:
   // buySignal  = (/* indicator logic */);
   // sellSignal = (/* indicator logic */);

   double sl = 0, tp = 0;
   if(buySignal)
   {
      sl = Ask - StopLossPips * Point * 10;
      tp = Ask + TakeProfitPips * Point * 10;

      int ticket = OrderSend(Symbol(), OP_BUY, Lots, Ask, Slippage, sl, tp,
                             "EA BUY", MagicNumber, 0, clrGreen);
   }
   else if(sellSignal)
   {
      sl = Bid + StopLossPips * Point * 10;
      tp = Bid - TakeProfitPips * Point * 10;

      int ticket = OrderSend(Symbol(), OP_SELL, Lots, Bid, Slippage, sl, tp,
                             "EA SELL", MagicNumber, 0, clrRed);
   }
}
