#property copyright "EarnForex.com"
#property link      "https://www.earnforex.com/metatrader-indicators/TD-Sequential-Ultimate/"
#property version   "1.01"

#property description "Shows setups and countdowns based on Tom DeMark's Sequential method."
#property description "TDST support and resistance levels are marked too."
#property description "Optional alerts available."

/* 
   For iCustom():

   Buffer #0 - TDST Resistance: actual price level. EMPTY_VALUE on empty value.
   Buffer #1 - TDST Support: actual price level. EMPTY_VALUE on empty value.
   Buffer #2 - Setup: candle number - positive for Buy Setup, negative for Sell Setup. 0 on empty value.
   Buffer #3 - Countdown: candle number - positive for Buy Countdown, negative for Sell Countdown. 0 on empty value.
   Buffer #4 - Setup Perfection: 1.0 for Buy Setup Perfection, -1.0 for Sell Setup Perfection. 0 on empty value.
*/

#property indicator_chart_window
#property indicator_buffers 5 // +3 buffers for usage with iCustom(), they won't be displayed by the indicator.
#property indicator_plots 5 // Only two are actually displayed. Three others are necessary for iCustom().
#property indicator_color1 clrRed
#property indicator_type1  DRAW_LINE
#property indicator_style1 STYLE_DASH
#property indicator_width1 1
#property indicator_label1 "TDST Resistance"
#property indicator_color2 clrGreen
#property indicator_type2  DRAW_LINE
#property indicator_style2 STYLE_DASH
#property indicator_width2 1
#property indicator_label2 "TDST Support"
#property indicator_type3  DRAW_NONE
#property indicator_color3 clrNONE
#property indicator_label3 "Setup"
#property indicator_type4  DRAW_NONE
#property indicator_label4 "Countdown"
#property indicator_color4 clrNONE
#property indicator_type5  DRAW_NONE
#property indicator_label5 "Perfection"
#property indicator_color5 clrNONE

input group "Main"
input color BuySetupColor  = clrLime;
input color SellSetupColor = clrRed;
input color CountdownColor = clrOrange;
input string FontFace      = "Verdana";
input int FontSize         = 12;
input int ArrowWidth       = 2;
input int PixelDistance    = 3;
input string Prefix        = "TDS_";
input group "Alerts"
input bool AlertOnSetup = false;
input bool AlertOnPerfecting = false;
input bool AlertOnCountdown13 = false;
input bool AlertOnSupportResistance = false;
input bool AlertNative       = false;
input bool AlertEmail        = false;
input bool AlertNotification = false;

// Support and resistance buffers - shown on the chart.
double Resistance[], Support[];
// These buffers will be used only by other indicators or EAs calling this one via iCustom().
double Setup[], Countdown[], Perfection[];

uint FontPixelHeight;

enum ENUM_COUNT_TYPE
{
   COUNT_TYPE_BUY_SETUP,
   COUNT_TYPE_SELL_SETUP,
   COUNT_TYPE_BUY_COUNTDOWN,
   COUNT_TYPE_SELL_COUNTDOWN,
   COUNT_TYPE_BUY_PERFECTION,
   COUNT_TYPE_SELL_PERFECTION
};

enum ENUM_ALERT_TYPE
{
   ALERT_TYPE_SETUP_BUY,
   ALERT_TYPE_SETUP_SELL,
   ALERT_TYPE_PERFECTING_BUY,
   ALERT_TYPE_PERFECTING_SELL,
   ALERT_TYPE_COUNT13_BUY,
   ALERT_TYPE_COUNT13_SELL,
   ALERT_TYPE_SUPPORT,
   ALERT_TYPE_RESISTANCE
};

int OnInit()
{
   SetIndexBuffer(0, Resistance, INDICATOR_DATA);
   SetIndexBuffer(1, Support, INDICATOR_DATA);
   SetIndexBuffer(2, Setup, INDICATOR_DATA);
   SetIndexBuffer(3, Countdown, INDICATOR_DATA);
   SetIndexBuffer(4, Perfection, INDICATOR_DATA);

   ArraySetAsSeries(Resistance, true);
   ArraySetAsSeries(Support, true);
   ArraySetAsSeries(Setup, true);
   ArraySetAsSeries(Countdown, true);
   ArraySetAsSeries(Perfection, true);
   
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Calculate the height of the font in pixels - will be needed later to space counts and arrows.
   string text = "0"; // Any dummy digit text to get its height.
   // Get the height of the text based on font and its size. Negative because OS-dependent, *10 because set in 1/10 of pt.
   TextSetFont(FontFace, FontSize * -10);
   uint w; // Dummy variable, not used anywhere except this call.
   TextGetSize(text, w, FontPixelHeight);
   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) 
{
   ObjectsDeleteAll(0, Prefix);
}
  
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &Time[],
                const double &open[],
                const double &High[],
                const double &Low[],
                const double &Close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   ArraySetAsSeries(Time, true);
   ArraySetAsSeries(High, true);
   ArraySetAsSeries(Low, true);
   ArraySetAsSeries(Close, true);
   
   static int Setup_Buy = 0;
   static datetime Setup_Buy_First_Candle = 0;
   static double Setup_Buy_Highest_High = 0;
   static double Setup_Buy_Highest_High_Candidate = 0;
   static double Setup_Buy_6_Low = 0;
   static double Setup_Buy_7_Low = 0;
   
   static bool No_More_Countdown_Buy_Until_Next_Buy_Setup = false;
   static bool Setup_Buy_Perfected = false;
   static bool Setup_Buy_Needs_Perfecting = false;
   
   static int Countdown_Buy = 0;
   static double Countdown_Buy_8_Close = 0;
   
   static int Setup_Sell = 0;
   static datetime Setup_Sell_First_Candle = 0;
   static double Setup_Sell_Lowest_Low = 0;
   static double Setup_Sell_Lowest_Low_Candidate = 0;
   static double Setup_Sell_6_High = 0;
   static double Setup_Sell_7_High = 0;
   
   static bool No_More_Countdown_Sell_Until_Next_Sell_Setup = false;
   static bool Setup_Sell_Perfected = false;
   static bool Setup_Sell_Needs_Perfecting = false;
   
   static int Countdown_Sell = 0;
   static double Countdown_Sell_8_Close = 0;
   
   if (rates_total < 7) return(0); // Not enough bars to start anything.
   int counted_bars = prev_calculated > 0 ? prev_calculated - 1 : 0;
   if (counted_bars < 0)  return(-1);
   int limit = MathMin(rates_total - 1 - counted_bars, rates_total - 6); // "- 6" because "+ 5" is used in the cycle.
   if (limit < 1) return(prev_calculated); // Data not yet ready.

   // Need to reset everything because prev_calculated is set to 0 when big chunks of new data are synced.
   if (prev_calculated == 0)
   {
      Setup_Buy = 0;
      Setup_Buy_First_Candle = 0;
      Setup_Buy_Highest_High = 0;
      Setup_Buy_6_Low = 0;
      Setup_Buy_7_Low = 0;
   
      No_More_Countdown_Buy_Until_Next_Buy_Setup = false;
      Setup_Buy_Perfected = false;
      Setup_Buy_Needs_Perfecting = false;
   
      Countdown_Buy = 0;
      Countdown_Buy_8_Close = 0;
   
      Setup_Sell = 0;
      Setup_Sell_First_Candle = 0;
      Setup_Sell_Lowest_Low = 0;
      Setup_Sell_6_High = 0;
      Setup_Sell_7_High = 0;
   
      No_More_Countdown_Sell_Until_Next_Sell_Setup = false;
      Setup_Sell_Perfected = false;
      Setup_Sell_Needs_Perfecting = false;
   
      Countdown_Sell = 0;
      Countdown_Sell_8_Close = 0;
      
      ObjectsDeleteAll(0, Prefix);
      
      for (int i = 0; i < rates_total; i++)
      {
         Setup[i] = 0;
         Countdown[i] = 0;
         Perfection[i] = 0;
         Support[i] = EMPTY_VALUE;
         Resistance[i] = EMPTY_VALUE;
      }
   }
      
   for (int i = limit; i > 0; i--)
   {
      Setup[i] = 0;
      Countdown[i] = 0;
      Perfection[i] = 0;
      // Cancel S/R or propgate them:
      if ((Resistance[i + 1] != EMPTY_VALUE) && (Close[i] > Resistance[i + 1]))
      {
         Resistance[i] = EMPTY_VALUE;
         if (AlertOnSupportResistance) DoAlert(i, ALERT_TYPE_RESISTANCE);
      }
      else Resistance[i] = Resistance[i + 1];
      if ((Support[i + 1] != EMPTY_VALUE) && (Close[i] < Support[i + 1]))
      {
         Support[i] = EMPTY_VALUE;
         if (AlertOnSupportResistance) DoAlert(i, ALERT_TYPE_SUPPORT);
      }
      else Support[i] = Support[i + 1];
      Resistance[0] = EMPTY_VALUE; Support[0] = EMPTY_VALUE; // Always empty for current candle.
      
      // Buy Setup.

      // Price Flip check + 
      // First Buy Setup candle + 
      // Setup_Buy == 0 for when no previous Buy Setup present. Setup_Buy == 9 for when one Buy Setup follows another:
      if ((Close[i + 1] >= Close[i + 5]) && (Close[i] < Close[i + 4]) && ((Setup_Buy == 0) || (Setup_Buy == 9))) 
      {
         Setup_Buy = 1;
         PutCount(COUNT_TYPE_BUY_SETUP, IntegerToString(Setup_Buy), Time[i], Low[i]);
         Setup_Buy_First_Candle = Time[i];  // Remember the first candle to wipe the Setup if it fails before completing.
         Setup_Buy_Highest_High_Candidate = High[i];
         Setup[i] = Setup_Buy;
      }
      // Buy Setup candles - second through nine:
      else if ((Close[i] < Close[i + 4]) && (Setup_Buy > 0) && (Setup_Buy < 9))
      {
         Setup_Buy++;
         Setup[i] = Setup_Buy;
         PutCount(COUNT_TYPE_BUY_SETUP, IntegerToString(Setup_Buy), Time[i], Low[i]);
         if (Setup_Buy_Highest_High_Candidate < High[i]) Setup_Buy_Highest_High_Candidate = High[i];
         
         // These are needed for perfection checks.
         if (Setup_Buy == 6) Setup_Buy_6_Low = Low[i];
         if (Setup_Buy == 7) Setup_Buy_7_Low = Low[i];
         
         if (Setup_Buy == 9)
         {
            Countdown_Sell = 0; // Reset Sell Countdown.
            No_More_Countdown_Sell_Until_Next_Sell_Setup = true;
            if (AlertOnSetup) DoAlert(i, ALERT_TYPE_SETUP_BUY);
            Setup_Buy_Perfected = false; // Will be checked farther.
            Setup_Buy_Needs_Perfecting = true;
            No_More_Countdown_Buy_Until_Next_Buy_Setup = false;
            Setup_Sell = 0;
            Setup_Buy_Highest_High = Setup_Buy_Highest_High_Candidate;
            for (int j = i; j < i + 9; j++)
            {
               Resistance[j] = Setup_Buy_Highest_High;
               if (High[j] == Setup_Buy_Highest_High) break;
            }
            // Check perfecting:
            // Setup candle #8:
            if ((Low[i + 1] < Setup_Buy_6_Low) && (Low[i + 1] < Setup_Buy_7_Low))
            {
               Setup_Buy_Perfected = true;
               Setup_Buy_Needs_Perfecting = false;
               Perfection[i + 1] = 1;
               PutCount(COUNT_TYPE_BUY_PERFECTION, "233", Time[i + 1], High[i + 1]); // Arrow up.
               if (AlertOnPerfecting) DoAlert(i + 1, ALERT_TYPE_PERFECTING_BUY);
            }
            // Countdown can also start on this candle but farther in the code.
         }
      }
      // Buy Setup broken:
      else if ((Close[i] >= Close[i + 4]) && (Setup_Buy != 9) && (Setup_Buy != 0))
      {
         RemoveCount(COUNT_TYPE_BUY_SETUP, Setup_Buy_First_Candle, Setup_Buy, Time); // Remove number objects for this Buy Setup.
         Setup_Buy = 0;
         Setup_Buy_First_Candle = 0;
         Setup_Buy_Highest_High_Candidate = 0;
         Setup_Buy_Needs_Perfecting = false;
         Setup_Buy_Perfected = false;
      }

      // Buy Countdown check.
      if ((!No_More_Countdown_Buy_Until_Next_Buy_Setup) && ((Setup_Buy == 9) || (Countdown_Buy > 0))) // Have a completed Buy Setup or a started Countdown.
      {
         if (Countdown_Buy < 13)
         {
            if (Close[i] <= Low[i + 2])
            {
               if (Countdown_Buy < 12) // Normal condition for Countdown candles from 1 through 12.
               {
                  Countdown_Buy++;
                  if (Countdown_Buy == 8) Countdown_Buy_8_Close = Close[i]; // Remember 8th Countdown close for checking the 13th.
                  Countdown[i] = Countdown_Buy;
                  PutCount(COUNT_TYPE_BUY_COUNTDOWN, IntegerToString(Countdown_Buy), Time[i], Low[i]);
               }
               else if (Low[i] < Countdown_Buy_8_Close) // Special condition for Countdown candle 13.
               {
                  Countdown_Buy++;
                  Countdown[i] = Countdown_Buy;
                  PutCount(COUNT_TYPE_BUY_COUNTDOWN, IntegerToString(Countdown_Buy), Time[i], Low[i]);
                  if (AlertOnCountdown13) DoAlert(i, ALERT_TYPE_COUNT13_BUY);
               }
               else // Failed Countdown candles 13 are marked with +.
               {
                  Countdown[i] = 14;
                  PutCount(COUNT_TYPE_BUY_COUNTDOWN, "+", Time[i], Low[i]);
               }
            }
         }
      }
      
      // Check if Countdown is broken.
      if (Countdown_Buy > 1) // Have a Buy Countdown that can be interrupted.
      {
         if ((Low[i] > Setup_Buy_Highest_High) && (Close[i + 1] > Setup_Buy_Highest_High))
         {
            Countdown_Buy = 0;
            Setup_Buy = 0;
         }
      }
      // Check if Setup is perfected.
      if ((!Setup_Buy_Perfected) && (Setup_Buy_Needs_Perfecting)) // Setup Buy candles #9+.
      {
         if ((Low[i] < Setup_Buy_6_Low) && (Low[i] < Setup_Buy_7_Low))
         {
            Setup_Buy_Perfected = true;
            Setup_Buy_Needs_Perfecting = false;
            Perfection[i] = 1;
            PutCount(COUNT_TYPE_BUY_PERFECTION, "233", Time[i], High[i]); // Arrow up.
            if (AlertOnPerfecting) DoAlert(i, ALERT_TYPE_PERFECTING_BUY);
         }
      }
      
      // Sell Setup.

      // Price Flip check + 
      // First Sell Setup candle + 
      // Setup_Sell == 0 for when no previous Sell Setup present. Setup_Sell == 9 for when one Sell Setup follows another:
      if ((Close[i + 1] <= Close[i + 5]) && (Close[i] > Close[i + 4]) && ((Setup_Sell == 0) || (Setup_Sell == 9)))
      {
         Setup_Sell = 1;
         PutCount(COUNT_TYPE_SELL_SETUP, IntegerToString(Setup_Sell), Time[i], High[i]);
         Setup_Sell_First_Candle = Time[i];  // Remember the first candle to wipe the Setup if it fails before completing.
         Setup_Sell_Lowest_Low_Candidate = Low[i];
         Setup[i] = -Setup_Sell;
      }
      // Sell Setup candles - second through nine:
      else if ((Close[i] > Close[i + 4]) && (Setup_Sell > 0) && (Setup_Sell < 9))
      {
         Setup_Sell++;
         Setup[i] = -Setup_Sell;
         PutCount(COUNT_TYPE_SELL_SETUP, IntegerToString(Setup_Sell), Time[i], High[i]);
         if (Setup_Sell_Lowest_Low_Candidate > Low[i]) Setup_Sell_Lowest_Low_Candidate = Low[i];
         
         // These are needed for perfection checks.
         if (Setup_Sell == 6) Setup_Sell_6_High = High[i];
         if (Setup_Sell == 7) Setup_Sell_7_High = High[i];
         
         if (Setup_Sell == 9)
         {
            Countdown_Buy = 0; // Reset Buy Countdown.
            No_More_Countdown_Buy_Until_Next_Buy_Setup = true;
            if (AlertOnSetup) DoAlert(i, ALERT_TYPE_SETUP_SELL);
            Setup_Sell_Perfected = false; // Will be checked farther.
            Setup_Sell_Needs_Perfecting = true;
            No_More_Countdown_Sell_Until_Next_Sell_Setup = false;
            Setup_Buy = 0;
            Setup_Sell_Lowest_Low = Setup_Sell_Lowest_Low_Candidate;
            for (int j = i; j < i + 9; j++)
            {
               Support[j] = Setup_Sell_Lowest_Low;
               if (Low[j] == Setup_Sell_Lowest_Low) break;
            }
            // Check perfecting:
            // Setup candle #8:
            if ((High[i + 1] > Setup_Sell_6_High) && (High[i + 1] > Setup_Sell_7_High))
            {
               Setup_Sell_Perfected = true;
               Setup_Sell_Needs_Perfecting = false;
               Perfection[i + 1] = -1;
               PutCount(COUNT_TYPE_SELL_PERFECTION, "234", Time[i + 1], Low[i + 1]); // Arrow down.
               if (AlertOnPerfecting) DoAlert(i + 1, ALERT_TYPE_PERFECTING_SELL);
            }
            // Countdown can also start on this candle but farther in the code.
         }
      }
      // Sell Setup broken:
      else if ((Close[i] <= Close[i + 4]) && (Setup_Sell != 9) && (Setup_Sell != 0))
      {
         RemoveCount(COUNT_TYPE_SELL_SETUP, Setup_Sell_First_Candle, Setup_Sell, Time); // Remove number objects for this Sell Setup.
         Setup_Sell = 0;
         Setup_Sell_First_Candle = 0;
         Setup_Sell_Lowest_Low_Candidate = 0;
         Setup_Sell_Needs_Perfecting = false;
         Setup_Sell_Perfected = false;
      }
      
      // Sell Countdown check.
      if ((!No_More_Countdown_Sell_Until_Next_Sell_Setup) && ((Setup_Sell == 9) || (Countdown_Sell > 0))) // Have a completed Sell Setup or a started Countdown.
      {
         if (Countdown_Sell < 13)
         {
            if (Close[i] >= High[i + 2])
            {
               if (Countdown_Sell < 12) // Normal condition for Countdown candles from 1 through 12.
               {
                  Countdown_Sell++;
                  if (Countdown_Sell == 8) Countdown_Sell_8_Close = Close[i]; // Remember 8th Countdown close for checking the 13th.
                  Countdown[i] = -Countdown_Sell;
                  PutCount(COUNT_TYPE_SELL_COUNTDOWN, IntegerToString(Countdown_Sell), Time[i], High[i]);
               }
               else if (High[i] > Countdown_Sell_8_Close) // Special condition for Countdown candle 13.
               {
                  Countdown_Sell++;
                  Countdown[i] = -Countdown_Sell;
                  PutCount(COUNT_TYPE_SELL_COUNTDOWN, IntegerToString(Countdown_Sell), Time[i], High[i]);
                  if (AlertOnCountdown13) DoAlert(i, ALERT_TYPE_COUNT13_SELL);
               }
               else // Failed Countdown candles 13 are marked with +.
               {
                  Countdown[i] = -14;
                  PutCount(COUNT_TYPE_SELL_COUNTDOWN, "+", Time[i], High[i]);
               }
            }
         }
      }
      
      // Check if Countdown is broken.
      if (Countdown_Sell > 0) // Have a Sell Countdown that can be interrupted.
      {
         if ((High[i] < Setup_Sell_Lowest_Low) && (Close[i + 1] < Setup_Sell_Lowest_Low))
         {
            Countdown_Sell = 0;
            Setup_Sell = 0;
         }
      }
      // Check if Setup is perfected.
      if ((!Setup_Sell_Perfected) && (Setup_Sell_Needs_Perfecting)) // Setup Sell candles #9+.
      {
         if ((High[i] > Setup_Sell_6_High) && (High[i] > Setup_Sell_7_High))
         {
            Setup_Sell_Perfected = true;
            Setup_Sell_Needs_Perfecting = false;
            Perfection[i] = -1;
            PutCount(COUNT_TYPE_SELL_PERFECTION, "234", Time[i], Low[i]); // Arrow down.
            if (AlertOnPerfecting) DoAlert(i, ALERT_TYPE_PERFECTING_SELL);
         }
      }
   }

   return(rates_total);
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if (id == CHARTEVENT_CHART_CHANGE) RedrawVisibleLabels();
}

void PutCount(const ENUM_COUNT_TYPE count_type, const string s, const datetime time, const double price)
{
	string name = Prefix;
	color colour = clrNONE;
	int level = 0;
	ENUM_OBJECT object_type = OBJ_TEXT;
	bool adjust_for_height = false;
	
	switch(count_type)
	{
	   case COUNT_TYPE_BUY_SETUP:
	   name += "BS";
	   colour = BuySetupColor;
	   level = 1;
	   break;
	   case COUNT_TYPE_SELL_SETUP:
	   name += "SS";
	   colour = SellSetupColor;
	   level = -1;
	   adjust_for_height = true;
	   break;
	   case COUNT_TYPE_BUY_COUNTDOWN:
	   name += "BC";
	   colour = CountdownColor;
  	   level = 2;
	   break;
	   case COUNT_TYPE_SELL_COUNTDOWN:
	   name += "SC";
	   colour = CountdownColor;
	   level = -2;
	   adjust_for_height = true;
	   break;
	   case COUNT_TYPE_BUY_PERFECTION:
	   name += "BP";
	   colour = BuySetupColor;
	   level = 3;
	   object_type = OBJ_ARROW;
	   break;
	   case COUNT_TYPE_SELL_PERFECTION:
	   name += "SP";
	   colour = SellSetupColor;
	   level = -3;
	   object_type = OBJ_ARROW;
	   adjust_for_height = true;
	   break;
	}
	
	name += IntegerToString((int)time);

	ObjectCreate(0, name, object_type, 0, time, price);
	ObjectSetInteger(0, name, OBJPROP_COLOR, colour);
	ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
	ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
	if ((count_type == COUNT_TYPE_BUY_PERFECTION) || (count_type == COUNT_TYPE_SELL_PERFECTION))
	{
	   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, StringToInteger(s));
	   ObjectSetInteger(0, name, OBJPROP_WIDTH, ArrowWidth);
	}
	else
	{
   	ObjectSetInteger(0, name, OBJPROP_FONTSIZE, FontSize);
   	ObjectSetString(0, name, OBJPROP_FONT, FontFace);
	   ObjectSetString(0, name, OBJPROP_TEXT, s);
	   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_UPPER);
   }
	
	RedrawOneWickLabel(name, time, price, level);
}

// level - positional level above (-) and below the candles (+).
void RedrawOneWickLabel(const string name, const datetime time, const double price, const int level)
{
   int x, y, cw;
   datetime t;
   double p, p_0;

   if (ObjectFind(0, name) == -1) return;

   int distance = 0;
   if (level < 0) distance = level * (int)FontPixelHeight + level * PixelDistance; // Objects above the candle should be additionally adjusted for their own height.
   else distance = (level - 1) * (int)FontPixelHeight + level * PixelDistance;

   // Needed only for y; x is used as a dummy.
   ChartTimePriceToXY(0, 0, time, price, x, y);

   ChartXYToTimePrice(0, x, y + distance, cw, t, p);

   // Went above the screen - MT5 ChartXYToTimePrice will invert the offset, so we need to adjust it.
   if (y + distance < 0) 
   {
      // Get the price of Y = 0.
      ChartXYToTimePrice(0, x, 0, cw, t, p_0);
      p = p_0 + (p_0 - p); // Return the price to its "above the screen edge" position.
   }

   ObjectSetDouble(0, name, OBJPROP_PRICE, p);
}

void RedrawVisibleLabels()
{
   int visible_bars = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   int first_bar = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   int last_bar = first_bar - visible_bars + 1;

   // Process all bars on the current screen.
   // Cycle through all possible object names based on prefix + count_type_name + timestamp.   
   for (int i = first_bar; i >= last_bar; i--)
   {
      datetime time = iTime(Symbol(), Period(), i);
      double low = iLow(Symbol(), Period(), i);
      double high = iHigh(Symbol(), Period(), i);
      string time_string = IntegerToString((int)time);
      RedrawOneWickLabel(Prefix + "BS" + time_string, time, low, 1);
      RedrawOneWickLabel(Prefix + "SS" + time_string, time, high, -1);
      RedrawOneWickLabel(Prefix + "BC" + time_string, time, low, 2);
      RedrawOneWickLabel(Prefix + "SC" + time_string, time, high, -2);
      RedrawOneWickLabel(Prefix + "BP" + time_string, time, low, 3);
      RedrawOneWickLabel(Prefix + "SP" + time_string, time, high, -3);
   }
   
   ChartRedraw();
}

// Remove number objects for a given setup.
void RemoveCount(const ENUM_COUNT_TYPE count_type, const datetime begin, const int n, const datetime &Time[])
{
   string name_start = Prefix;
   if (count_type == COUNT_TYPE_BUY_SETUP) name_start += "BS";
   else if (count_type == COUNT_TYPE_SELL_SETUP) name_start += "SS";

   int begin_candle = iBarShift(Symbol(), Period(), begin, true);

   if (begin_candle == -1) return; // Some data error.
   
   for (int i = begin_candle; i > begin_candle - n; i--)
   {
      string name = name_start + IntegerToString(Time[i]);
      ObjectDelete(0, name);
   }
}

void DoAlert(int i, ENUM_ALERT_TYPE alert_type)
{
	if (i > 2) return; // i == 2 the earliest possible alert event that should be reacted on.
	
	string main_text = "Sequential: " + Symbol() + " @ " + EnumToString((ENUM_TIMEFRAMES)Period());
	string email_subject = main_text;
	//string 
	switch(alert_type)
	{
	   case ALERT_TYPE_SETUP_BUY:
	   main_text += " Buy Setup completed by " + TimeToString(iTime(Symbol(), Period(), i)) + " candle.";
      email_subject += " Buy Setup";
	   break;
	   case ALERT_TYPE_SETUP_SELL:
	   main_text += " Sell Setup completed by " + TimeToString(iTime(Symbol(), Period(), i)) + " candle.";
      email_subject += " Sell Setup";
	   break;
	   case ALERT_TYPE_PERFECTING_BUY:
	   main_text += " Buy Setup Perfected by " + TimeToString(iTime(Symbol(), Period(), i)) + " candle.";
      email_subject += " Buy Perfecting";
	   break;
	   case ALERT_TYPE_PERFECTING_SELL:
	   main_text += " Sell Setup Perfected by " + TimeToString(iTime(Symbol(), Period(), i)) + " candle.";
      email_subject += " Sell Perfecting";
	   break;
	   case ALERT_TYPE_COUNT13_BUY:
	   main_text += " Buy Countdown completed by " + TimeToString(iTime(Symbol(), Period(), i)) + " candle.";
      email_subject += " Buy Countdown";
	   break;
	   case ALERT_TYPE_COUNT13_SELL:
	   main_text += " Sell Countdown completed by " + TimeToString(iTime(Symbol(), Period(), i)) + " candle.";
      email_subject += " Sell Countdown";
	   break;
	   case ALERT_TYPE_RESISTANCE:
	   main_text += " TDST Resistance broken by " + TimeToString(iTime(Symbol(), Period(), i)) + " candle.";
      email_subject += " Buy TDST Resistance";
	   break;
	   case ALERT_TYPE_SUPPORT:
	   main_text += " TDST Support broken by " + TimeToString(iTime(Symbol(), Period(), i)) + " candle.";
      email_subject += " TDST Support";
	   break;
	}

	if (AlertNative) Alert(main_text);
	if (AlertEmail) SendMail(email_subject, main_text);
	if (AlertNotification) SendNotification(main_text);
}
//+------------------------------------------------------------------+