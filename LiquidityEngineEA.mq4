#property strict
#property description "Liquidity Engine EA for MT4"
#property version   "1.00"

input double   Lots                = 0.10;
input int      Slippage            = 3;
input int      ATRPeriod           = 14;
input int      PivotLength         = 10;
input int      MaxZonesPerSide     = 4;
input double   ZoneSeparationATR   = 1.2;
input double   SweepDistanceATR    = 1.5;
input double   ZoneProximityATR    = 0.6;
input int      MaxZoneAgeBars      = 300;
input bool     TrendFilterEnabled  = true;
input int      TrendFastMA         = 21;
input int      TrendSlowMA         = 50;
input int      MagicNumber         = 20261114;
input bool     OneTradeAtATime     = true;
input double   StopATRMultiplier   = 0.5;
input double   RiskReward          = 2.0;
input int      MinBarsBetweenTrades = 12;

struct Zone
{
   double level;
   bool   isSupply;
   int    born;
   bool   valid;
   bool   mitigated;
};

Zone gSupplyZones[];
Zone gDemandZones[];
int gLastTradeBar = 0;

int OnInit()
{
   ArrayResize(gSupplyZones, 0);
   ArrayResize(gDemandZones, 0);
   gLastTradeBar = 0;
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   if(Bars < 50)
      return;

   if(OneTradeAtATime && HasOpenPosition())
      return;

   RefreshZones();
   DetectSwingZones();

   if(Bars - gLastTradeBar < MinBarsBetweenTrades)
      return;

   bool buySignal  = false;
   bool sellSignal = false;

   if(TrendFilterEnabled)
   {
      if(IsBullishTrend())
         buySignal = CanBuyFromSweep();
      if(IsBearishTrend())
         sellSignal = CanSellFromSweep();
   }
   else
   {
      buySignal  = CanBuyFromSweep();
      sellSignal = CanSellFromSweep();
   }

   if(buySignal)
   {
      OpenBuyTrade();
   }
   else if(sellSignal)
   {
      OpenSellTrade();
   }
}

bool IsBullishTrend()
{
   double fastMA = iMA(Symbol(), Period(), TrendFastMA, 0, MODE_EMA, PRICE_CLOSE, 0);
   double slowMA = iMA(Symbol(), Period(), TrendSlowMA, 0, MODE_EMA, PRICE_CLOSE, 0);
   return(fastMA > slowMA);
}

bool IsBearishTrend()
{
   double fastMA = iMA(Symbol(), Period(), TrendFastMA, 0, MODE_EMA, PRICE_CLOSE, 0);
   double slowMA = iMA(Symbol(), Period(), TrendSlowMA, 0, MODE_EMA, PRICE_CLOSE, 0);
   return(fastMA < slowMA);
}

double GetAtrValue()
{
   return(iATR(Symbol(), Period(), ATRPeriod, 0));
}

bool HasOpenPosition()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
            return true;
      }
   }
   return false;
}

bool IsNearZone(double price, bool isSupply)
{
   double atr = GetAtrValue();
   double zoneDistance = atr * ZoneProximityATR;

   if(isSupply)
   {
      for(int i = 0; i < ArraySize(gSupplyZones); i++)
      {
         if(gSupplyZones[i].valid && MathAbs(price - gSupplyZones[i].level) <= zoneDistance)
            return true;
      }
   }
   else
   {
      for(int i = 0; i < ArraySize(gDemandZones); i++)
      {
         if(gDemandZones[i].valid && MathAbs(price - gDemandZones[i].level) <= zoneDistance)
            return true;
      }
   }
   return false;
}

bool CanBuyFromSweep()
{
   double atr = GetAtrValue();
   for(int i = 0; i < ArraySize(gSupplyZones); i++)
   {
      Zone z = gSupplyZones[i];
      if(!z.valid)
         continue;

      double zoneWidth = atr * 0.5;
      double lowNow = Low[0];
      double closeNow = Close[0];
      double entryThreshold = z.level + zoneWidth;

      // Sweep of supply zone: price pushes above the zone and then closes back below it
      if(lowNow > z.level && closeNow < z.level && Close[1] < z.level)
      {
         // Check aggressive approach and trend alignment
         if(MathAbs(closeNow - z.level) <= atr * SweepDistanceATR)
            return true;
      }

      // Alternative approach: price is near supply zone and pushing lower
      if(closeNow > z.level && closeNow < entryThreshold)
      {
         if(MathAbs(closeNow - z.level) <= atr * SweepDistanceATR)
            return true;
      }
   }
   return false;
}

bool CanSellFromSweep()
{
   double atr = GetAtrValue();
   for(int i = 0; i < ArraySize(gDemandZones); i++)
   {
      Zone z = gDemandZones[i];
      if(!z.valid)
         continue;

      double zoneWidth = atr * 0.5;
      double highNow = High[0];
      double closeNow = Close[0];
      double entryThreshold = z.level - zoneWidth;

      // Sweep of demand zone: price pushes below the zone and then closes back above it
      if(highNow < z.level && closeNow > z.level && Close[1] > z.level)
      {
         if(MathAbs(closeNow - z.level) <= atr * SweepDistanceATR)
            return true;
      }

      if(closeNow < z.level && closeNow > entryThreshold)
      {
         if(MathAbs(closeNow - z.level) <= atr * SweepDistanceATR)
            return true;
      }
   }
   return false;
}

bool DetectSwingZones()
{
   double atr = GetAtrValue();
   int left = PivotLength;
   int right = PivotLength;

   double pivotHigh = iHighest(Symbol(), Period(), MODE_HIGH, left + right + 1, left);
   double pivotLow = iLowest(Symbol(), Period(), MODE_LOW, left + right + 1, left);

   if(!IsNewBar())
      return false;

   if(!IsZoneDuplicate(pivotHigh, true) && pivotHigh > 0)
   {
      AddZone(pivotHigh, true);
   }

   if(!IsZoneDuplicate(pivotLow, false) && pivotLow > 0)
   {
      AddZone(pivotLow, false);
   }

   return true;
}

bool IsNewBar()
{
   static datetime lastTime = 0;
   datetime now = Time[0];
   if(lastTime == 0)
   {
      lastTime = now;
      return true;
   }
   if(now != lastTime)
   {
      lastTime = now;
      return true;
   }
   return false;
}

bool IsZoneDuplicate(double level, bool isSupply)
{
   double atr = GetAtrValue();
   double sep = atr * ZoneSeparationATR;

   if(isSupply)
   {
      for(int i = 0; i < ArraySize(gSupplyZones); i++)
      {
         if(gSupplyZones[i].valid && MathAbs(gSupplyZones[i].level - level) <= sep)
            return true;
      }
   }
   else
   {
      for(int i = 0; i < ArraySize(gDemandZones); i++)
      {
         if(gDemandZones[i].valid && MathAbs(gDemandZones[i].level - level) <= sep)
            return true;
      }
   }
   return false;
}

void AddZone(double level, bool isSupply)
{
   double atr = GetAtrValue();
   int maxSide = MaxZonesPerSide;

   if(isSupply)
   {
      if(ArraySize(gSupplyZones) >= maxSide)
      {
         for(int i = 0; i < ArraySize(gSupplyZones); i++)
         {
            if(!gSupplyZones[i].valid)
            {
               ArrayRemove(gSupplyZones, i);
               break;
            }
         }
      }

      Zone z;
      z.level = level;
      z.isSupply = true;
      z.born = Bars;
      z.valid = true;
      z.mitigated = false;
      ArrayResize(gSupplyZones, ArraySize(gSupplyZones) + 1);
      gSupplyZones[ArraySize(gSupplyZones)-1] = z;
   }
   else
   {
      if(ArraySize(gDemandZones) >= maxSide)
      {
         for(int i = 0; i < ArraySize(gDemandZones); i++)
         {
            if(!gDemandZones[i].valid)
            {
               ArrayRemove(gDemandZones, i);
               break;
            }
         }
      }

      Zone z;
      z.level = level;
      z.isSupply = false;
      z.born = Bars;
      z.valid = true;
      z.mitigated = false;
      ArrayResize(gDemandZones, ArraySize(gDemandZones) + 1);
      gDemandZones[ArraySize(gDemandZones)-1] = z;
   }
}

void RefreshZones()
{
   double atr = GetAtrValue();
   int bars = Bars;

   for(int i = 0; i < ArraySize(gSupplyZones); i++)
   {
      if(!gSupplyZones[i].valid)
         continue;

      if((bars - gSupplyZones[i].born) > MaxZoneAgeBars)
      {
         gSupplyZones[i].valid = false;
         continue;
      }

      if(Close[0] > gSupplyZones[i].level && Close[1] > gSupplyZones[i].level)
      {
         if(MathAbs(Close[0] - gSupplyZones[i].level) <= atr * ZoneProximityATR)
         {
            gSupplyZones[i].mitigated = true;
            gSupplyZones[i].valid = false;
         }
      }
   }

   for(int i = 0; i < ArraySize(gDemandZones); i++)
   {
      if(!gDemandZones[i].valid)
         continue;

      if((bars - gDemandZones[i].born) > MaxZoneAgeBars)
      {
         gDemandZones[i].valid = false;
         continue;
      }

      if(Close[0] < gDemandZones[i].level && Close[1] < gDemandZones[i].level)
      {
         if(MathAbs(Close[0] - gDemandZones[i].level) <= atr * ZoneProximityATR)
         {
            gDemandZones[i].mitigated = true;
            gDemandZones[i].valid = false;
         }
      }
   }
}

void OpenBuyTrade()
{
   double atr = GetAtrValue();
   double stopLoss = MarketInfo(Symbol(), MODE_BID) - (StopATRMultiplier * atr);
   double takeProfit = stopLoss + (MathAbs(stopLoss - Ask) * RiskReward);

   int ticket = OrderSend(Symbol(), OP_BUY, Lots, Ask, Slippage, stopLoss, takeProfit,
                         "Liquidity Engine BUY", MagicNumber, 0, clrGreen);

   if(ticket > 0)
   {
      gLastTradeBar = Bars;
   }
}

void OpenSellTrade()
{
   double atr = GetAtrValue();
   double stopLoss = MarketInfo(Symbol(), MODE_ASK) + (StopATRMultiplier * atr);
   double takeProfit = stopLoss - (MathAbs(Bid - stopLoss) * RiskReward);

   int ticket = OrderSend(Symbol(), OP_SELL, Lots, Bid, Slippage, stopLoss, takeProfit,
                         "Liquidity Engine SELL", MagicNumber, 0, clrRed);

   if(ticket > 0)
   {
      gLastTradeBar = Bars;
   }
}

bool ArrayRemove(Zone &arr[], int index)
{
   int size = ArraySize(arr);
   if(index < 0 || index >= size)
      return false;

   for(int i = index; i < size - 1; i++)
      arr[i] = arr[i + 1];

   ArrayResize(arr, size - 1);
   return true;
}

bool IsValidOrderTicket(int ticket)
{
   return(ticket > 0);
}

// Helper use for debugging in strategy tester / logs
void LogZoneStatus(string msg)
{
   Print(msg);
}
