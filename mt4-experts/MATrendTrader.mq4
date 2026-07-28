//+------------------------------------------------------------------+
//|                                                MATrendTrader.mq4 |
//|                                         Copyright 2025, YourName |
//|                                                 https://mql5.com |
//| 30.07.2025 - Initial release                                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, YourName"
#property link      "https://mql5.com"
#property version   "1.00"
#property strict

#include <TradeManager.mqh>

input int barsToHold = 60; // Num bars to wait before closing
input double minProfitRatio = 0.04; // Min profit percentage to close
input int minSL = 40; // Minimum starting SL
input int trailingStop = 70; // Trailing Stop distance
input int MADistThreshold = 20; // Dist between MAs less than to open
input double minTrendThreshold = 0.0; // Slow MA trend greater than to open
input int trendHistLength = 120; // Num bars used to determine trend

// --- Global Variables ---
COrderManager* g_tradeManager = NULL;
datetime g_lastBarTime = 0;  
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  //---
  if (IsTesting()) {
    if (ChartApplyTemplate(ChartID(), "MATrendTrader.tpl")) Print("Template loaded");
    else Print("Template not found");
  }
  g_tradeManager = new COrderManager(42427, _Symbol);
  Print("Expert Initialized");
  //---
  return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  if(CheckPointer(g_tradeManager) != POINTER_INVALID) {
    delete g_tradeManager; 
    g_tradeManager = NULL;
  }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
  //---
  if (g_tradeManager.IsTradeOpen()) {
    if (IsNewBar()) {
      MoveSL();
    }
    CheckCloseIndicators();
  }
  else {
    int action = CheckOpenIndicators();
    if (action == OP_BUY) {
      OpenBuy();
    }
    else if (action == OP_SELL) {
      OpenSell();
    }
  }
}

bool IsNewBar()
{
   datetime curBarTime = iTime(_Symbol, 0, 0); 
   if(g_lastBarTime != curBarTime) {
      g_lastBarTime = curBarTime;
      return(true);      
   }
   return(false);
}

void MoveSL() {
  if (!g_tradeManager.IsTradeOpen()) return;
  COrder *order = g_tradeManager.GetActiveManagedTrade();
  int type = order.GetOrderType();
  double slowMA = iMA(_Symbol, 0, 104, 0, MODE_SMA, PRICE_CLOSE, 1);
  if (type == OP_BUY) {
    double currentSL = (Bid - order.GetStopLoss()) / Point / PIPS_TO_POINTS_FACTOR(_Symbol);
    double newSL = trailingStop * 10;//MathMax(50, (Bid - slowMA) / Point);
    g_tradeManager.MoveTrailingStop(newSL, false);
  }
  else {
    double currentSL = (order.GetStopLoss() - Ask) / Point / PIPS_TO_POINTS_FACTOR(_Symbol);
    double newSL = trailingStop * 10;//MathMax(50, (slowMA - Ask) / Point);
    g_tradeManager.MoveTrailingStop(newSL, false);
  }
}

int CheckOpenIndicators() {
  double fastMA = iMA(_Symbol, 0, 9, 0, MODE_SMA, PRICE_CLOSE, 1); // 9 MA from previous bar
  double medMA = iMA(_Symbol, 0, 26, 0, MODE_SMA, PRICE_CLOSE, 1); // 26 MA from previous bar
  double slowMA = iMA(_Symbol, 0, 104, 0, MODE_SMA, PRICE_CLOSE, 1); // 104 MA from previous bar
  double stochMain = iStochastic(_Symbol, 0, 5, 3, 3, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
  double dSlowMA = (slowMA - iMA(_Symbol, 0, 104, 0, MODE_SMA, PRICE_CLOSE, trendHistLength)) / trendHistLength / Point;

  bool openBuy = false;
  bool openSell = false;

  openBuy = Bid > fastMA && fastMA > medMA && dSlowMA > minTrendThreshold && MathAbs(fastMA - medMA) / Point < MADistThreshold && MathAbs(fastMA - medMA) / Point < MADistThreshold;// && (prevFastMA <= prevSlowMA || prevMedMA <= prevSlowMA);
  openSell = Ask < fastMA && fastMA < medMA && dSlowMA < -minTrendThreshold && MathAbs(fastMA - medMA) / Point < MADistThreshold;// && (prevFastMA >= prevSlowMA || prevMedMA >= prevSlowMA);

  if (openBuy) return OP_BUY;
  if (openSell) return OP_SELL;
  return -1;
}

void CheckCloseIndicators() {
  if (!g_tradeManager.IsTradeOpen()) return;
  COrder *order = g_tradeManager.GetActiveManagedTrade();
  if (order.GetOpenBars() < barsToHold) return;
  int type = order.GetOrderType();
  double stochMain = iStochastic(_Symbol, 0, 5, 3, 3, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 0);
  double fastMA = iMA(_Symbol, 0, 9, 0, MODE_SMA, PRICE_CLOSE, 0); // 9 MA from previous bar
  double medMA = iMA(_Symbol, 0, 26, 0, MODE_SMA, PRICE_CLOSE, 0); // 26 MA from previous bar
  double slowMA = iMA(_Symbol, 0, 160, 0, MODE_SMA, PRICE_CLOSE, 0); // 104 MA from previous bar
  double dSlowMA = (slowMA - iMA(_Symbol, 0, 160, 0, MODE_SMA, PRICE_CLOSE, trendHistLength)) / trendHistLength / Point;

  bool closeBuy = (order.GetNetProfit() > minProfitRatio * AccountBalance() && (stochMain > 80));
  closeBuy = closeBuy || dSlowMA < 0 || Bid < fastMA;
  closeBuy = closeBuy && type == OP_BUY;
  bool closeSell = (order.GetNetProfit() > minProfitRatio * AccountBalance() && (stochMain < 20));
  closeSell = closeSell || dSlowMA > 0 || Ask > fastMA;
  closeSell = closeSell && type == OP_SELL;

  if (closeBuy || closeSell) {
    g_tradeManager.CloseCurrentTrade();
  }
}

void OpenBuy() {
  double slowMA = iMA(_Symbol, 0, 104, 0, MODE_SMA, PRICE_CLOSE, 1);
  double sl = calcSL(OP_BUY);
  if (sl < minSL) return;
  double lots = g_tradeManager.CalcLotsFromRisk(sl, 0.02);
  double tp = sl * 2;
  g_tradeManager.OpenTrade(OP_BUY, lots, sl, tp);
}

void OpenSell() {
  
  double slowMA = iMA(_Symbol, 0, 104, 0, MODE_SMA, PRICE_CLOSE, 1);
  double sl = calcSL(OP_SELL);
  if (sl < minSL) return;
  double lots = g_tradeManager.CalcLotsFromRisk(sl, 0.02);
  double tp = sl * 2;
  g_tradeManager.OpenTrade(OP_SELL, lots, sl, tp);
}

double calcSL(int type) {
  double stop = MarketInfo(_Symbol, MODE_STOPLEVEL);
  if (type == OP_BUY) {
    int index = iLowest(NULL, 0, MODE_LOW, 104);
    double low = iLow(NULL, 0, index);
    stop = MathMax(stop, (Bid - low) / Point / PIPS_TO_POINTS_FACTOR(_Symbol) + 10);
  }
  else if (type == OP_SELL) {
    int index = iHighest(NULL, 0, MODE_LOW, 104);
    double high = iHigh(NULL, 0, index);
    stop = MathMax(stop, (high - Ask) / Point / PIPS_TO_POINTS_FACTOR(_Symbol) + 10);
  }

  return stop;;
}
//+------------------------------------------------------------------+
