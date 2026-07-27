//+------------------------------------------------------------------+
//|                                                    DQNTrader.mq4 |
//|                                     Copyright 2022, Nathan Adams |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, Nathan Adams"
#property link "https://www.mql5.com"
#property version "1.00"
#property strict
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
#include <TradeManager.mqh>
#include <UITools.mqh>
#include <ANeuralNet.mqh>
#include <DataManager.mqh>
#include <TechnicalAnalysis.mqh>
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
extern double exploreProb = 1.0; // Current exploration probability
extern int sampleFreq = 28800; // Num seconds to wait between transitions
extern int maxMoves = 20; // Num moves to make before training
extern int batchSize = 20; // Training minibatch size
extern int trainingIterationsPerBatch = 20; // Num iterations to train
extern int weightCopyInterval = 100; // Frequency to copy nnet weights
extern double learningRate = 0.0001; // Neural net learning rate (eta)
extern double momentum = 0.95; // Neural net momentum (alpha)
extern bool train = true; // Enter training loop periodically
extern bool explore = true; // Incorporate random actions
extern bool restrictToStrategy = false; // Filter open actions through strategy
extern bool randomActionIsStrategy = true;
extern int exploreDeltaDenom = 5000; // Num of actions until exporation is zero
extern bool trainInOneTest = false;
extern int maxOpenOrders = 1;
extern double lossRiskPercent = 0.03;
extern double equityPercent = 1.0;
extern int minStop = 500;
extern string netDataFileName = "DQN.data";
extern string dataFileName = "DQNTransitions.data";
extern int optimizationPasses = 100; // Decrement as a counter
extern bool autoIncrementExploreProb = false;
extern int minBarsToHold = 48; // Minumum num of bars to hold a trade before closing
//+------------------------------------------------------------------+
//| Global Constants                                                 |
//+------------------------------------------------------------------+
// Trade Actions  
enum times {TEN_SEC = 10, THIRTY_SEC = 30, MINUTE = 60, THREE_MIN = 180, FIVE_MIN = 300, TEN_MIN = 600, FIFTEEN_MIN = 900};
      
enum all_actions {ACTION_OPEN_BUY_ORDER = OP_BUY, ACTION_OPEN_SELL_ORDER = OP_SELL, ACTION_WAIT_TO_OPEN, ACTION_WAIT_TO_MODIFY,
              ACTION_CLOSE_ORDER, ACTION_STOP_UP_1, ACTION_STOP_UP_10, ACTION_STOP_LVL_1, ACTION_STOP_LVL_2};
const string action_names[] = {"OPEN BUY ORDER", "OPEN SELL ORDER", "WAIT TO OPEN","WAIT TO MODIFY",
                        "CLOSE ORDER", "STOP +1", "STOP +10", "STOP M15", "STOP H1"};        
//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
int fastMAPeriod = 20; int slowMAPeriod = 40; int stopLossMAPeriod = 120; int MACDBasePeriod = 120;
COrderManager orderManager;
CButton *btnAutoBuy;  CButton *btnAutoSell;
CArrayObj *labels;    CLabel *lblExplrDelta;  CLabel *lblScore; CLabel *lblOpenScore; CLabel *lblMoveCount; CLabel *lblError;
CArrayInt *actions;
DQN *net;
CArrayObj *episodeData;
CData *trainingData;
CArrayDouble *inputData;
int selectedAction = ACTION_WAIT_TO_OPEN;
CArrayDouble *inputData_2;
int openTicket;
bool isOpenTransition = false;
datetime lastTime = 0;
double initialStopLoss = 0;
int moveCount = 0;
int totalMoveCount = 0;
int lastActionTaken = -1;
int streak = 0;
double currentPips = 0;
double totalPips = 0;
double initialBalance;
double maxBalance;
double maxOrderProfit = 0, minOrderProfit = 0;
double initialLossRisk = 0;
bool isEpisodeSaved = false;
datetime episodeStartTime;
CArrayDouble stopLevels;
CTechAnalyzer techAnalyzer(), H1TechAnalyzer(PERIOD_H1, clrBlue), H4TechAnalyzer(PERIOD_H4, clrGreen);
double profitLastBar = 0, lossRiskLastBar = 0;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  Print("Initializing");

  // Actions to use
  actions = new CArrayInt();
  actions.Add(ACTION_OPEN_BUY_ORDER);
  actions.Add(ACTION_OPEN_SELL_ORDER);
  actions.Add(ACTION_WAIT_TO_OPEN);
  actions.Add(ACTION_WAIT_TO_MODIFY);
  actions.Add(ACTION_CLOSE_ORDER); 
  actions.Add(ACTION_STOP_UP_1); 
  actions.Add(ACTION_STOP_UP_10);
  actions.Add(ACTION_STOP_LVL_1);
  actions.Add(ACTION_STOP_LVL_2);
  //actions.Add(ACTION_STOP_DOWN_1);
  //actions.Add(ACTION_STOP_DOWN_10);

  /******************** User interface ***********************************/
  //ChartApplyTemplate(0, "TrendTraderAI.tpl");
  btnAutoBuy = new CButton("BUTTON_AUTO_BUY", 10, 18, 70, 18, "Auto Buy");
  btnAutoSell = new CButton("BUTTON_AUTO_SELL", 100, 18, 70, 18, "Auto Sell");
  // Action lables
  labels = new CArrayObj();
  for (int i = 0; i < actions.Total(); i++){
    CLabel *label = new CLabel("LABEL_" + IntegerToString(i), 10, 36 + 16*i, "");
    labels.Add(label);
  }
  // Exploration delta label
  lblExplrDelta = new CLabel("LABEL_EXPLORE_DELTA", 10, 36 + 16*(labels.Total() + 1), "Explore delta = ");
  lblExplrDelta.SetColor(C'128,128,128');

  // Trade management score label
  lblScore = new CLabel("LABEL_SCORE", 300, 18, "");
  lblScore.SetColor(C'220,220,220');

  // Trade open score label
  lblOpenScore = new CLabel("LABEL_OPEN_SCORE", 300, 36, "");
  lblOpenScore.SetColor(C'220,220,220');

  // Move count label
  lblMoveCount = new CLabel("LABEL_MOVES", 600, 18, "");
  lblMoveCount.SetColor(C'220,220,220');

  // Recent Average Error label
  lblError = new CLabel("AVG_ERROR", 300, 54, "");
  lblError.SetColor(C'220,220,220');
  

  /******************* Data *******************************/
  inputData = new CArrayDouble();
  episodeData = new CArrayObj();
  inputData_2 = new CArrayDouble();
  trainingData = new CData();
  if (trainingData.Load("Buy" + dataFileName))
  {
    trainingData.NormalizeData();
    //CDataRecord *r = trainingData.At(trainingData.Total() - 1);
    Print(IntegerToString(trainingData.Total()) + " records loaded");
  }
  else
  {
    Print("Failed to load buy training data");
    Print("Starting new file");
    trainingData.Save("Buy" + dataFileName);
  }

  /******************* Reward and Training ****************************/
  initialBalance = AccountEquity();
  maxBalance = initialBalance;
  
  // Start at a random time
  lastTime = TimeCurrent() + sampleFreq * rand() % (16); 

  episodeStartTime = TimeCurrent();

  /******************* Testing ****************************************/
  /*if (exploreProb < 0.5 && (int)(exploreProb * 100) % 2 == 0){
    train = false;
    explore = false;
  }*/

  return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  //---
  Print("Total move count = ", totalMoveCount);

  // Delete buttons
  if (CheckPointer(btnAutoBuy) != POINTER_INVALID)
  {
    btnAutoBuy.Delete();
    delete btnAutoBuy;
  }
  if (CheckPointer(btnAutoSell) != POINTER_INVALID)
  {
    btnAutoSell.Delete();
    delete btnAutoSell;
  }

  // Delete labels
  if (CheckPointer(labels) != POINTER_INVALID){
    for (int i = 0; i < labels.Total(); i++){
      CLabel *label = labels.At(i);
      label.Delete();
    }
    delete labels;
  }
  lblExplrDelta.Delete();
  delete lblExplrDelta;
  lblScore.Delete();
  delete lblScore;
  lblOpenScore.Delete();
  delete lblOpenScore;
  lblMoveCount.Delete();
  delete lblMoveCount;
  lblError.Delete();
  delete lblError;

  if (CheckPointer(trainingData) != POINTER_INVALID)
  {
    finalizeEpisodeData();
    if (AccountEquity() > 1000 && exploreProb <= 0.0)
      trainingData.Save(StringFormat("%.3f", optimizationPasses + exploreProb) + "Buy" + dataFileName);
    trainingData.Save("Buy" + dataFileName);
    delete trainingData;
  }
  if (CheckPointer(net) != POINTER_INVALID){
    if (AccountEquity() > 1000 && exploreProb <= 0.0)
      net.Save(StringFormat("%.3f", optimizationPasses + exploreProb)  + "Buy" + netDataFileName);
    net.Save("Buy" + netDataFileName);
    delete net;
  }    
  if (CheckPointer(inputData) != POINTER_INVALID) delete inputData;
  if (CheckPointer(inputData_2) != POINTER_INVALID) delete inputData_2;
  if (CheckPointer(episodeData) != POINTER_INVALID) delete episodeData;
  if (CheckPointer(labels) != POINTER_INVALID) delete labels;  
  if (CheckPointer(lblExplrDelta) != POINTER_INVALID) delete lblExplrDelta;  
  if (CheckPointer(lblScore) != POINTER_INVALID) delete lblScore;  
  if (CheckPointer(lblMoveCount) != POINTER_INVALID) delete lblMoveCount;  
  if (CheckPointer(lblOpenScore) != POINTER_INVALID) delete lblOpenScore;
  if (CheckPointer(lblError) != POINTER_INVALID) delete lblError;
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(){
  // Check if open order has closed by stop-loss
  // If an order has closed, record data for neural net training
  for (int i = 0; i < orderManager.OpenOrderCount(); i++)
  {
    COrder *order = orderManager.GetOrder(i);
    maxOrderProfit = MathMax(maxOrderProfit, order.GetProfit());
    minOrderProfit = MathMin(minOrderProfit, order.GetProfit());
    if (order.IsClosed()){
      Print("***Stop Loss Hit***");
      if (train){
        if (inputData.Total() > 0){
          collectInputData(inputData_2);
          saveTransition();
        }
        finalizeTradeData(order.GetTicket());
      }
    }
  }

  
  // Keep order list updated
  orderManager.OrderAccounting();

  // Record environment state and act every sampleFreq
  if (TimeCurrent() > lastTime + MathMax(FIFTEEN_MIN, sampleFreq))
  {
    lastTime = TimeCurrent();  

    techAnalyzer.DrawUpperTrendLine(1, 49, 3, 2, 4);
    techAnalyzer.DrawLowerTrendLine(1, 49, 3, 2, 4);
    techAnalyzer.DrawResistanceLine(1, 49);
    techAnalyzer.DrawSupportLine(1, 49);
    H1TechAnalyzer.DrawUpperTrendLine(0, 48, 3, 2, 8);
    H1TechAnalyzer.DrawLowerTrendLine(0, 48, 3, 2, 8);
    H1TechAnalyzer.DrawResistanceLine(1, 49);
    H1TechAnalyzer.DrawSupportLine(1, 49);
    H4TechAnalyzer.DrawUpperTrendLine(0, 48, 3, 2, 8);
    H4TechAnalyzer.DrawLowerTrendLine(0, 48, 3, 2, 8);
    H4TechAnalyzer.DrawResistanceLine(1, 49);
    H4TechAnalyzer.DrawSupportLine(1, 49);

    if (train && inputData.Total() > 0)
    {
      // If inputData_1 has been recorded, collect inputData_2
      collectInputData(inputData_2);
      saveTransition();
    }

    // Manage open orders
    
    if (orderManager.OpenOrderCount() > 0){
      /*if (checkTrailingStopIndicators() == ACTION_STOP_UP_1) {
        stopLevels.Add(orderManager.GetOrder().GetOrderType() == OP_BUY ? iLow(NULL, PERIOD_H1, 1) : iHigh(NULL, PERIOD_H1, 1));
      }*/
      
      //if (checkCloseIndicators() == ACTION_STOP_UP_1){ 
        // Collect input data
        collectInputData(inputData);
        
        // Pick action
        COrder order(openTicket);
        selectedAction = pickAction(inputData);

        // Perform Action
        // Close orders
        if (selectedAction == ACTION_CLOSE_ORDER)
        {
          Print("Close order");
          closeOrders();
        }
        // Update stops
        else if (selectedAction == ACTION_STOP_UP_1 || selectedAction == ACTION_STOP_UP_10)
        {
          // Move the stop loss for all open orders
          //updateStops();
          moveStopsUp();
        }
        else if(selectedAction == ACTION_STOP_LVL_1 || selectedAction == ACTION_STOP_LVL_2){
          moveStopToCritLevel();
        }
        // Wait
        else if (selectedAction == ACTION_WAIT_TO_MODIFY)
        {
          // Wait - do nothing
        }
      //}
    }
    
    // Determine whether or not to open an order
    if (orderManager.OpenOrderCount() < maxOpenOrders && (IsTesting() || btnAutoBuy.isPressed() || btnAutoSell.isPressed())){
      
      // Collect input data
      collectInputData(inputData);
      // DQN picks decides when to open an order
      selectedAction = pickAction(inputData);  

      COrder *order = orderManager.GetOrder();
      // Decide what action to take
      if ((orderManager.OpenOrderCount() == 0 || selectedAction == order.GetOrderType()) /*&& TimeCurrent()/* - orderManager.GetLastTradeCloseTime() > FIFTEEN_MIN * 24*/)
      {
        if (selectedAction == ACTION_OPEN_BUY_ORDER) {
          openBuyOrder();
        }
        else if (selectedAction == ACTION_OPEN_SELL_ORDER) {
          openSellOrder();
        }
      }
      if (selectedAction == ACTION_WAIT_TO_OPEN){
        // Wait - do nothing
      }

    }   
  }

  // When not taking an action, train every so often
  else if (train && totalMoveCount >= maxMoves){
    // Train
    net.train(trainingIterationsPerBatch, batchSize);
    lblError.SetText("Error = " + DoubleToString(net.getRecentAverageError()));
    totalMoveCount = 0;
  }

}

//+------------------------------------------------------------------+
//| OnTick helper functions                                          |
//+------------------------------------------------------------------+
void openBuyOrder(){
  // If there is no open order, open one, or if the selected action is the same as an already open order, open another
  double limit;
  initialStopLoss = calcStopLoss(selectedAction);
  limit = calcProfitLimit(selectedAction);//3.0 * initialStopLoss;

  double lots = orderManager.CalcLotsFromRisk(initialStopLoss, lossRiskPercent / maxOpenOrders, equityPercent);
  
  int openOrderCount = orderManager.OpenOrderCount();

  orderManager.OpenBuyOrder(lots, initialStopLoss, limit);

  if (openOrderCount < orderManager.OpenOrderCount() && CheckPointer(orderManager.GetOrder(openOrderCount)) != POINTER_INVALID)
  {
    // Successfully opened an order
    openTicket = orderManager.GetOrder().GetTicket();
    COrder *newOrder = orderManager.GetOrder();
    maxOrderProfit = newOrder.GetProfit(); 
    minOrderProfit = newOrder.GetProfit();
    initialLossRisk = newOrder.GetLossRisk();
    isOpenTransition = true;
    lossRiskLastBar = newOrder.GetLossRisk();
  }
  else
  {
    // Failed to open the order
    collectInputData(inputData_2);
    saveTransition();
  }
}

void openSellOrder(){
  // If there is no open order, open one, or if the selected action is the same as an already open order, open another
  double limit;
  initialStopLoss = calcStopLoss(selectedAction);
  limit = calcProfitLimit(selectedAction);//3.0 * initialStopLoss;

  double lots = orderManager.CalcLotsFromRisk(initialStopLoss, lossRiskPercent / maxOpenOrders, equityPercent);
  int openOrderCount = orderManager.OpenOrderCount();

  orderManager.OpenSellOrder(lots, initialStopLoss, limit);
  

  if (openOrderCount < orderManager.OpenOrderCount() && CheckPointer(orderManager.GetOrder(openOrderCount)) != POINTER_INVALID)
  {
    // Successfully opened an order
    openTicket = orderManager.GetOrder().GetTicket();
    COrder *newOrder = orderManager.GetOrder();
    maxOrderProfit = newOrder.GetProfit(); 
    initialLossRisk = newOrder.GetLossRisk();
    isOpenTransition = true;
    lossRiskLastBar = newOrder.GetLossRisk();
  }
  else
  {
    // Failed to open the order
    collectInputData(inputData_2);
    saveTransition();
  }
}

void moveStopsUp(){
  for (int i = 0; i < orderManager.OpenOrderCount(); i++){
        COrder *order = orderManager.GetOrder(i);
        double stop = order.GetOrderType() == OP_BUY ? MathAbs(Bid - order.GetStopLoss()) / Point : MathAbs(order.GetStopLoss() - Ask) / Point;
        if (selectedAction == ACTION_STOP_UP_1)
        {
          stop -= 10;
        }
        else if (selectedAction == ACTION_STOP_UP_10)
        {
          stop -= 100;
        }
        stop = MathMax(stop, minStop);
        if (CheckPointer(order) != POINTER_INVALID)
        {
          orderManager.MoveTrailingStopByTicket(stop, order.GetTicket(), false);
        }
      }
}

void moveStopToCritLevel(){
  for (int i = 0; i < orderManager.OpenOrderCount(); i++){
    COrder *order = orderManager.GetOrder(i);
    double stop = 0;
    if (order.GetOrderType() == OP_BUY){
      if (selectedAction == ACTION_STOP_LVL_1){
        stop = (Bid - H1TechAnalyzer.GetSupportPrice(1, 49)) / Point;
      }
      else if (selectedAction == ACTION_STOP_LVL_2){
        stop = (Bid - H4TechAnalyzer.GetSupportPrice(1, 49)) / Point;
      }
    }
    else if (order.GetOrderType() == OP_SELL){
      if (selectedAction == ACTION_STOP_LVL_1){
        stop = (H1TechAnalyzer.GetResistancePrice(1, 49) - Ask) / Point;
      }
      else if (selectedAction == ACTION_STOP_LVL_2){
        stop = (H4TechAnalyzer.GetResistancePrice(1, 49) - Ask) / Point;
      }
    }
    stop = MathMax(stop, minStop);
    if (CheckPointer(order) != POINTER_INVALID)
    {
      orderManager.MoveTrailingStopByTicket(stop, order.GetTicket(), false);
    }
  }
}

void closeOrders(){
  COrder *order = orderManager.GetOrder(orderManager.OpenOrderCount() - 1);
  if (CheckPointer(order) != POINTER_INVALID)
  {
    int ticket = order.GetTicket();
    orderManager.CloseOrderByTicket(ticket);
    collectInputData(inputData_2);
    saveTransition();
    finalizeTradeData(ticket);
  }
  else {
    /*collectInputData(inputData_2);
    saveTransition(-200);*/
  }
}


//+------------------------------------------------------------------+
//|  Triple MACD Strategy Functions                                  |
//+------------------------------------------------------------------+
int getStrategyAction(){
  if (orderManager.OpenOrderCount() > 0){
    int result = checkCloseIndicators();
    if (result == ACTION_WAIT_TO_MODIFY)
      return ACTION_STOP_UP_10;
    else return result;
  }
  else {
    return checkOpenIndicators();
  }
}

int checkOpenIndicators()
{
  // ------- Indicators ------------
  datetime currentTime = iTime(NULL, 0, 0);
  double sto_Main = iStochastic(NULL, PERIOD_H4, 5, 3, 3, MODE_SMA, 0, MODE_MAIN, 1);
  double sto_Sig = iStochastic(NULL, PERIOD_H4, 5, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 1);
  double last_sto_Main = iStochastic(NULL, 0, 5, 3, 3, MODE_SMA, 0, MODE_MAIN, 1);
  double last_sto_Sig = iStochastic(NULL, 0, 5, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 1);

  double MACDMainM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 1);
  double MACDSigM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 1);
  double prevMACDMainM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 2);
  double prevMACDSigM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 2);
  double MACDMainH4 = iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 1);
  double MACDSigH4 = iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 1);
  double MACDMainH1 = iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 1);
  double MACDSigH1 = iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 1);

  double slowMA = iMA(NULL, PERIOD_M15, 26*4*4, 0, MODE_SMA, PRICE_CLOSE, 0);
  double fastMA = iMA(NULL, PERIOD_M15, 12*4*4, 0, MODE_SMA, PRICE_CLOSE, 0);

  bool buy_sig = true, sell_sig = true;
  for (int i = 0; i < 1; i++){
    //buy_sig = buy_sig && iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, i) > 0 && iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, i) > 0;
    buy_sig = buy_sig && iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, i) > iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, i);
    //buy_sig = buy_sig && iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, i) > 0 && iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, i) > 0;
    buy_sig = buy_sig && iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, i) > iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, i);
    //sell_sig = sell_sig && iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, i) < 0 && iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, i) < 0;
    sell_sig = sell_sig && iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, i) < iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, i);
    //sell_sig = sell_sig && iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, i) < 0 && iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, i) < 0;
    sell_sig = sell_sig && iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, i) < iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, i);
  }

  //buy_sig = buy_sig && sto_Main < 20 && sto_Main > sto_Sig;
  //sell_sig = sell_sig && sto_Main > 80 && sto_Main < sto_Sig;

  if (buy_sig && MACDMainM15 > MACDSigM15 && prevMACDMainM15 <= prevMACDSigM15 && MACDMainH4 < 0) return ACTION_OPEN_BUY_ORDER;
  else if (sell_sig && MACDMainM15 < MACDSigM15 && prevMACDMainM15 >= prevMACDSigM15 && MACDMainH4 > 0) return ACTION_OPEN_SELL_ORDER;
  else return ACTION_WAIT_TO_OPEN;

}

int checkCloseIndicators() {
  double MACDMainM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 1);
  double MACDSigM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 1);
  double prevMACDMainM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 2);
  double prevMACDSigM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 2);
  double MACDMainH4 = iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0);
  double MACDSigH4 = iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 0);
  double MACDMainH1 = iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0);
  double MACDSigH1 = iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 0);
  double prevMACDMainH1 = iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 2);
  double prevMACDSigH1 = iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 2);

  double sto_Main = iStochastic(NULL, 0, 5, 3, 3, MODE_SMA, 0, MODE_MAIN, 0);
  double sto_Sig = iStochastic(NULL, 0, 5, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 0);
  double prev_sto_Main = iStochastic(NULL, 0, 5, 3, 3, MODE_SMA, 0, MODE_MAIN, 1);
  double prev_sto_Sig = iStochastic(NULL, 0, 5, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 1);

  COrder *order = orderManager.GetOrder(orderManager.OpenOrderCount() - 1);
  if (CheckPointer(order) != POINTER_INVALID && TimeCurrent() - order.GetOpenTime() > FIFTEEN_MIN * minBarsToHold )
  {
    if (order.GetOrderType() == OP_BUY ){
      //if (checkOpenIndicators() == ACTION_OPEN_SELL_ORDER && order.GetProfit() > lossRiskPercent * 1.0 * (AccountEquity() - order.GetProfit())) return ACTION_CLOSE_ORDER;
      //if (prev_sto_Sig > 80 && sto_Main < sto_Sig && MACDMainH4 > MACDSigH4) return ACTION_CLOSE_ORDER;
      //if (MACDMainM15 < MACDSigM15 && order.GetProfit() > lossRiskPercent * 2.0 * (AccountEquity() - order.GetProfit())) return ACTION_CLOSE_ORDER;
      if (sto_Sig > 80 && sto_Main < sto_Sig && MACDMainM15 < MACDSigM15 && order.GetProfit() > lossRiskPercent * 1.0 * (AccountEquity() - order.GetProfit())) return ACTION_CLOSE_ORDER;
    }
    else {
      //if (checkOpenIndicators() == ACTION_OPEN_BUY_ORDER && order.GetProfit() > lossRiskPercent * 1.0 * (AccountEquity() - order.GetProfit())) return ACTION_CLOSE_ORDER; 
      //if (prev_sto_Sig < 20 && sto_Main > sto_Sig && MACDMainH4 < MACDSigH4) return ACTION_CLOSE_ORDER;
      //if (MACDMainM15 > MACDSigM15 && order.GetProfit() > lossRiskPercent * 2.0 * (AccountEquity() - order.GetProfit())) return ACTION_CLOSE_ORDER;
      if (sto_Sig < 20 && sto_Main > sto_Sig && MACDMainM15 > MACDSigM15 && order.GetProfit() > lossRiskPercent * 1.0 * (AccountEquity() - order.GetProfit())) return ACTION_CLOSE_ORDER;
    }
  }

  return ACTION_WAIT_TO_MODIFY;
}

int checkTrailingStopIndicators() {
  double sto_Main = iStochastic(NULL, PERIOD_H1, 5, 3, 3, MODE_SMA, 0, MODE_MAIN, 1);
  double sto_Sig = iStochastic(NULL, PERIOD_H1, 5, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 1);
  double last_sto_Main = iStochastic(NULL, PERIOD_H1, 5, 3, 3, MODE_SMA, 0, MODE_MAIN, 3);
  double last_sto_Sig = iStochastic(NULL, PERIOD_H1, 5, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 3);

  double MACDMainM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 1);
  double MACDSigM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 1);
  double MACDMainH4 = iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 1);
  double MACDSigH4 = iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 1);
  double MACDMainH1 = iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 1);
  double MACDSigH1 = iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 1);

  COrder *order = orderManager.GetOrder(orderManager.OpenOrderCount() - 1);
  if (CheckPointer(order) != POINTER_INVALID && TimeCurrent() - order.GetOpenTime() > FIFTEEN_MIN * minBarsToHold)
  {
    if (order.GetOrderType() == OP_BUY){
      //if (MACDSigM15 > MACDMainM15) return ACTION_STOP_UP_1;
      if (sto_Main > sto_Sig && last_sto_Main < last_sto_Sig) return ACTION_STOP_UP_1;
    }
    else {
      //if (MACDSigM15 < MACDMainM15) return ACTION_STOP_UP_1;
      if (sto_Main < sto_Sig && last_sto_Main > last_sto_Sig) return ACTION_STOP_UP_1;
    }
  }

  return ACTION_WAIT_TO_MODIFY;
}

void updateStops()
{
  for (int n = 0; n < orderManager.OpenOrderCount(); n++)
  {
    COrder *order = orderManager.GetOrder(n);
    if (order.GetOrderType() == OP_BUY)
    {
      double currentStop = (Bid - order.GetStopLoss()) / Point;
      double limit = (order.GetProfitLimit() - Bid) / Point;
      for (int i = stopLevels.Total() - 1; i >= 0; i--){
        double stop = (Bid - stopLevels.At(i)) / Point;
        /*if (stop < currentStop && stop > calcStopLoss(OP_BUY)){
          orderManager.MoveTrailingStop(stop, order);
          break;
        }
        else*/ if (true || limit < 1.0 * calcStopLoss(OP_BUY)){
          orderManager.MoveTrailingStop(MathMax(stop, calcStopLoss(OP_BUY)), order);
          //orderManager.MoveTrailingStop(calcStopLoss(OP_BUY), order);
          break;
        }
      }
      
    }
    else if (order.GetOrderType() == OP_SELL)
    {
      double currentStop = (order.GetStopLoss() - Ask) / Point;
      double limit = (Ask - order.GetProfitLimit()) / Point;
      for (int i = stopLevels.Total() - 1; i >= 0; i--){
        double stop = (stopLevels.At(i) - Ask) / Point;
        /*if (stop < currentStop && stop > calcStopLoss(OP_SELL)){
          orderManager.MoveTrailingStop(stop, order);
          break;
        }
        else*/ if (true || limit < 1.0 * calcStopLoss(OP_SELL)){
          orderManager.MoveTrailingStop(MathMax(stop, calcStopLoss(OP_SELL)), order);
          //orderManager.MoveTrailingStop(calcStopLoss(OP_BUY), order);
          break;
        }
      }
      
    }
  }
}

double calcStopLoss(int orderType)
{
  //return 500;//**************************


  double stop = 0;
  if (orderType == ACTION_OPEN_BUY_ORDER)
  {
    //stop = MathMax((Bid - low) / Point, (Bid - iMA(NULL, 0, stopLossMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 0)) / Point);
    //stop = (Bid - getSupport(3)) / Point + 20;
    stop = (Bid * 0.005) / Point;
    stop = stop < minStop ? minStop : stop;
  }
  else
  {
    //stop = MathMax((high - Ask) / Point, (iMA(NULL, 0, stopLossMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 0) - Ask) / Point);
    //stop = (getResistance(3) - Ask) / Point + 20;
    stop = (Ask * 0.005) / Point;
    // Make sure it is larger than the min specified
    stop = stop < minStop ? minStop : stop;
  }

  return stop;
}

double calcProfitLimit(int orderType)
{
  
  // *******************************
  return calcStopLoss(orderType) * 3;
  // *****everything below will be skipped if the line above is uncommented
  
}

double getSupport(int level = 1){
  double low = iLow(NULL, PERIOD_D1, 1);
  double high = iHigh(NULL, PERIOD_D1, 1);
  double close = iClose(NULL, PERIOD_D1, 1);
  double pivotPoint = (high + low + close) / 3.0;

  double s1 = 2 * pivotPoint - high;
  if (level == 1) return s1;
  double r1 = 2 * pivotPoint - low;
  double s2 = pivotPoint - (r1 - s1);
  if (level == 2) return s2;
  double r2 = (pivotPoint - s1) + r1;
  double s3 = pivotPoint - (r2 - s2);
  if (level == 3) return s3;
  
  return 0.0;
}
//+------------------------------------------------------------------+
//| Deep Q-Learning Functions                                        |
//+------------------------------------------------------------------+
void collectInputData(CArrayDouble *data)
{
    data.Clear();
    int recordCount = trainingData.Total() + episodeData.Total() + inputData.Total();
    int startIndex = 0;
    //double medPrice = (Ask + Bid) / 2;
    double basePrice = 0;//CheckPointer(order) != POINTER_INVALID ? order.GetOpenPrice() : iLow(NULL, PERIOD_D1, 1);//getSwingLow(320);
    /* Data being recorded */


    //******************************* Data for open trade *************************************
    COrder *order = orderManager.GetOrder();
    // Current profit
    data.Add(CheckPointer(order) != POINTER_INVALID ? order.GetProfit() : 0);
    // Max profit
    data.Add(CheckPointer(order) != POINTER_INVALID ? maxOrderProfit : 0);
    // Min profit
    data.Add(CheckPointer(order) != POINTER_INVALID ? minOrderProfit : 0);
    // Current equity
    data.Add(AccountEquity());
    data.Add(AccountEquity() - initialBalance);
    if (recordCount == 0)
    {
      trainingData.setNamedDataRange(startIndex, data.Total(), "CURRENT EQUITY");
      startIndex = data.Total();
    }

    // Current trade state: none, buy, or sell
    if (CheckPointer(order) != POINTER_INVALID){
      data.Add(order.GetOrderType() == OP_BUY ? 1 : -1);
    }
    else data.Add(0);
    if (recordCount == 0)
    {
      trainingData.setNamedDataRange(startIndex, data.Total(), "TRADE_STATE");
      startIndex = data.Total();
    }

    data.Add(CheckPointer(order) != POINTER_INVALID ? order.GetProfitLimit() - basePrice : 0);
    data.Add(CheckPointer(order) != POINTER_INVALID ? order.GetStopLoss() - basePrice : 0);
      //data.Add(CheckPointer(o) != POINTER_INVALID ? order.GetOpenPrice() - basePrice : 0);
    if (recordCount == 0)
    {
      trainingData.setNamedDataRange(startIndex, data.Total(), "CURRENT_TRADE_DATA");
      startIndex = data.Total();
    }

    // Time since first trade open
    //int openTime = CheckPointer(order) != POINTER_INVALID ? (int)(TimeCurrent() - order.GetOpenTime()) / 60 : 0;
    int openTime = CheckPointer(order) != POINTER_INVALID ? order.GetOpenBars() : 0;
    data.Add(openTime);
    if (recordCount == 0)
    {
      trainingData.setNamedDataRange(startIndex, data.Total(), "TIME SINCE OPEN");
      startIndex = data.Total();
    }

    //*********************** Data from indicators ******************************
    // MACD data 
    double MACDMainH4 = iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 1);
    double MACDSigH4 = iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 1);
    double MACDMainH1 = iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 1);
    double MACDSigH1 = iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 1);
    double MACDMainM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0);
    double MACDSigM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 0);
    
    data.Add(MACDMainM15);
    data.Add(MACDSigM15);
    //data.Add(MACDMainH1);
    //data.Add(MACDSigH1);
    //data.Add(MACDMainH4);
    //data.Add(MACDSigH4);
    if (recordCount == 0)
    {
      trainingData.setNamedDataRange(startIndex, data.Total(), "MACD_DATA");
      startIndex = data.Total();
    }

    // Stoch data
    double sto_Main = iStochastic(NULL, PERIOD_H4, 5, 3, 3, MODE_SMA, 0, MODE_MAIN, 1);
    double sto_Sig = iStochastic(NULL, PERIOD_H4, 5, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 1);
    double last_sto_Main = iStochastic(NULL, 0, 5, 3, 3, MODE_SMA, 0, MODE_MAIN, 1);
    double last_sto_Sig = iStochastic(NULL, 0, 5, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 1);
    
    data.Add(sto_Main);
    data.Add(sto_Sig);
    if (recordCount == 0)
    {
      trainingData.setNamedDataRange(startIndex, data.Total(), "STOCH_DATA");
      startIndex = data.Total();
    }

    // Index of last time price was at support/resistance level
    /*
    data.Add(techAnalyzer.GetResistanceIndex(1, 49));
    data.Add(techAnalyzer.GetSupportIndex(1, 49));
    data.Add(H1TechAnalyzer.GetResistanceIndex(1, 49));
    data.Add(H1TechAnalyzer.GetSupportIndex(1, 49));
    data.Add(H4TechAnalyzer.GetResistanceIndex(1, 49));
    data.Add(H4TechAnalyzer.GetSupportIndex(1, 49));
    if (recordCount == 0)
    {
      trainingData.setNamedDataRange(startIndex, data.Total(), "SUP_RES_INDICES");
      startIndex = data.Total();
    }*/

    // Current Price

    // Current support and resistance levels
    data.Add(techAnalyzer.GetResistancePrice(1, 49));
    data.Add(techAnalyzer.GetSupportPrice(1, 49));
    data.Add(H1TechAnalyzer.GetResistancePrice(1, 49));
    data.Add(H1TechAnalyzer.GetSupportPrice(1, 49));
    data.Add(H4TechAnalyzer.GetResistancePrice(1, 49));
    data.Add(H4TechAnalyzer.GetSupportPrice(1, 49));

    // recent bar data
    data.Add((Bid + Ask) / 2);
    for (int i = 1; i < 3; i++){
      //data.Add(iOpen(NULL, PERIOD_M15, i) - basePrice);
      data.Add(iLow(NULL, PERIOD_M15, i) - basePrice);
      data.Add(iHigh(NULL, PERIOD_M15, i) - basePrice);
      //data.Add(iClose(NULL, PERIOD_M15, i) - basePrice);
    }

    data.Add(techAnalyzer.GetUpperTLValue(0));
    data.Add(techAnalyzer.GetLowerTLValue(0));
    data.Add(H1TechAnalyzer.GetUpperTLValue(0));
    data.Add(H1TechAnalyzer.GetLowerTLValue(0));
    data.Add(H4TechAnalyzer.GetUpperTLValue(0));
    data.Add(H4TechAnalyzer.GetLowerTLValue(0));
    
    if (recordCount == 0)
    {
      trainingData.setNamedDataRange(startIndex, data.Total(), "CURRENT_PRICE_DATA");
      startIndex = data.Total();
    }
    
    // Data about the best fit line equations
    CArrayDouble *result = new CArrayDouble();
    techAnalyzer.GetUpperTLFitParams(result);
    data.Add(result.At(0));
    //data.Add(result.At(1));
    //data.Add(result.At(2));
    result.Clear();
    H1TechAnalyzer.GetUpperTLFitParams(result);
    data.Add(result.At(0));
    //data.Add(result.At(1));
    //data.Add(result.At(2));
    result.Clear();
    H4TechAnalyzer.GetUpperTLFitParams(result);
    data.Add(result.At(0));
    //data.Add(result.At(1));
    //data.Add(result.At(2));
    result.Clear();
    techAnalyzer.GetLowerTLFitParams(result);
    data.Add(result.At(0));
    //data.Add(result.At(1));
    //data.Add(result.At(2));
    result.Clear();
    H1TechAnalyzer.GetLowerTLFitParams(result);
    data.Add(result.At(0));
    //data.Add(result.At(1));
    //data.Add(result.At(2));
    result.Clear();
    H4TechAnalyzer.GetLowerTLFitParams(result);
    data.Add(result.At(0));
    //data.Add(result.At(1));
    //data.Add(result.At(2));
    result.Clear();
    delete result;

    if (recordCount == 0)
    {
      trainingData.setNamedDataRange(startIndex, data.Total(), "TL_EQN_DATA");
      startIndex = data.Total();
    }

    // Candle vectors
    for (int i = 1; i < 5; i++){
      data.Add(iClose(NULL, PERIOD_M15, i) - iOpen(NULL, PERIOD_M15, i));
    }
    if (recordCount == 0)
    {
      trainingData.setNamedDataRange(startIndex, data.Total(), "CANDLE_VECTORS");
      startIndex = data.Total();
    }

    // Validate data
    bool dataCheck = true;
    for (int i = 0; i < data.Total(); i++)
    {
      if (data.At(i) > 10000000)
      {
        Print(IntegerToString(i) + " is a questionable value: " + DoubleToString(data.At(i)) + " at " + TimeToString(TimeCurrent()) );
        dataCheck = false;
      }
    }
    // Create the network if it doesn't exist
    if (dataCheck && CheckPointer(net) == POINTER_INVALID)
    {
      initializeDQN(data.Total());
    }
    if (!dataCheck)
    {
      data.Clear();
    }
  
}

void initializeDQN(int numInputs, bool loadFile = true){
  if (CheckPointer(net) != POINTER_INVALID) delete net;
  net = new DQN();
  if (!loadFile || !net.Load("Buy" + netDataFileName))
  {
    Print("Unable to load net, starting new file");
    CArrayInt *buyActions = new CArrayInt();
    buyActions.Add(ACTION_OPEN_BUY_ORDER);
    buyActions.Add(ACTION_OPEN_SELL_ORDER);
    buyActions.Add(ACTION_WAIT_TO_OPEN);
    buyActions.Add(ACTION_WAIT_TO_MODIFY);
    buyActions.Add(ACTION_CLOSE_ORDER); 
    buyActions.Add(ACTION_STOP_UP_1); 
    buyActions.Add(ACTION_STOP_UP_10);
    buyActions.Add(ACTION_STOP_LVL_1);
    buyActions.Add(ACTION_STOP_LVL_2);
    //buyActions.Add(ACTION_STOP_DOWN_1);
    //buyActions.Add(ACTION_STOP_DOWN_10);
    net = new DQN(numInputs, buyActions, "Buy" + netDataFileName);
    net.setExplorDelta(exploreDeltaDenom);
    net.setExplorRate(exploreProb);
    delete buyActions;
  }
  net.setDefaultAction(ACTION_WAIT_TO_MODIFY);
  net.setDataSource(trainingData);
  net.setWeightCopyInterval(weightCopyInterval);
  net.setLearningRate(learningRate);
  net.setMomentum(momentum);
  //net.setActionWeight(2 /*ACTION_WAIT_TO_OPEN*/, MathMax(1, (int)(32 * exploreProb)));
  //net.setActionWeight(3 /*ACTION_WAIT_TO_MODIFY*/, MathMax(1, (int)(32 * exploreProb)));
  if (autoIncrementExploreProb) exploreProb = MathMax(0, exploreProb - 1.0 / MathMax(1, optimizationPasses));
  if (randomActionIsStrategy) net.setExplorRate(0);
  else if (!trainInOneTest) net.setExplorRate(exploreProb);
}

int pickAction(CArrayDouble *inData){
  CArrayDouble *data = new CArrayDouble();
  data.AssignArray(inData);
  trainingData.NormalizeInputData(data);
  int action = -1;
  CArrayInt *availActions = new CArrayInt();
  if (orderManager.OpenOrderCount() < maxOpenOrders){
    availActions.Add(ACTION_OPEN_BUY_ORDER);
    availActions.Add(ACTION_OPEN_SELL_ORDER);
    availActions.Add(ACTION_WAIT_TO_OPEN);
  }
  else if (orderManager.OpenOrderCount() > 0){
    COrder *order = orderManager.GetOrder();
    availActions.Add(ACTION_WAIT_TO_MODIFY);
    if (order.GetOpenBars() > 4){
      availActions.Add(ACTION_CLOSE_ORDER);
    }
    availActions.Add(ACTION_STOP_UP_1);
    availActions.Add(ACTION_STOP_UP_10);
    availActions.Add(ACTION_STOP_LVL_1);
    availActions.Add(ACTION_STOP_LVL_2);
  }
  
  lastActionTaken = selectedAction;
  action = net.pickAction(data, availActions, explore);
  if (randomActionIsStrategy){
    double r = (rand() % 10000) / 10000.0;
    if (r < exploreProb){
      action = getStrategyAction();
    }
  }
  // Update display
  Print("Action: ", action);
  for (int i = 0; i < actions.Total(); i++){
    CLabel *label = labels.At(i);
    string text = StringFormat(action_names[actions.At(i)] + ": %.4f", net.getActionValue(i));
    label.SetText(text);
    if (i == action){
      label.SetColor(C'0,255,0');
    } else {
      label.SetColor(C'128,128,128');
    }
  }
  lblExplrDelta.SetText("Exploration prob = " + DoubleToString(explore ? net.getExplorProb() : 0));
  moveCount++;
  totalMoveCount++;
  lblMoveCount.SetText(IntegerToString(moveCount) + " moves");
  delete data;
  delete availActions;
  return action;
}

void saveTransition(double reward = 0)
{
  if (train)
  {
    reward += getCurrentReward(selectedAction);
    if (MathAbs(reward) > 10000){
      Print("High reward");
    }
    
    COrder order(openTicket);
    // Update previous stop loss variable
    lossRiskLastBar = order.GetLossRisk();
    profitLastBar = order.GetProfit();

    // Keep score
    if (openTicket > -1 && selectedAction > ACTION_WAIT_TO_OPEN){
      lblScore.SetText("Last manag score: " + DoubleToString(reward));
    }

    CArrayDouble *selectedActions = new CArrayDouble();
    for (int i = 0; i < actions.Total(); i++)
    {
      selectedActions.Add(0.0);
    }
    
    if (inputData.Total() == inputData_2.Total() && inputData.Total() == net.getNumInputs())
    {
      selectedActions.Update(net.getActionIndex(selectedAction), 1.0);
      if (order.GetOrderType() == ACTION_OPEN_BUY_ORDER || order.GetOrderType() == ACTION_OPEN_SELL_ORDER){
        if (isOpenTransition){
          isOpenTransition = false;
        }
      }
      trainingData.AddTransition(new CDataRecord(TimeCurrent(), inputData, selectedActions, reward, inputData_2, openTicket));
    } 
    else {
      Print("Data Error: input1 total = " + IntegerToString(inputData.Total()) + " input2 total = " + IntegerToString(inputData_2.Total()));
      Print("Net inputs = " + IntegerToString(net.getNumInputs()));
      Print("Action Taken = " + action_names[selectedAction]);
      totalMoveCount -= episodeData.Total();
    }
    inputData = new CArrayDouble();
    inputData_2 = new CArrayDouble();
    
  }
}

double getCurrentReward(int action = -1){
  double reward = 0;
  double sto_Main = iStochastic(NULL, PERIOD_H4, 5, 3, 3, MODE_SMA, 0, MODE_MAIN, 1);
  double sto_Sig = iStochastic(NULL, PERIOD_H4, 5, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 1);
  double last_sto_Main = iStochastic(NULL, 0, 5, 3, 3, MODE_SMA, 0, MODE_MAIN, 2);
  double last_sto_Sig = iStochastic(NULL, 0, 5, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 2);

  double MACDMainM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 1);
  double MACDSigM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 1);
  double prevMACDMainM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 2);
  double prevMACDSigM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 2);
  double MACDMainH4 = iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 1);
  double MACDSigH4 = iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 1);
  double MACDMainH1 = iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 1);
  double MACDSigH1 = iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 1);
  
  if (selectedAction == ACTION_CLOSE_ORDER){
    COrder order(openTicket);
    reward += order.GetProfit();    
  }
  
  if (selectedAction > ACTION_WAIT_TO_OPEN)
  {
    COrder order(openTicket);
    double dProfit = order.GetProfit() - profitLastBar;
    double dRisk = order.GetLossRisk() - lossRiskLastBar;
    reward += dProfit;// + dRisk;
  }



  /* Open action rewards based on profit potential (max order profit calculated after order is closed) */
  double h1ChannelWidth = (H1TechAnalyzer.GetUpperTLValue() - H1TechAnalyzer.GetLowerTLValue());
  double h4ChannelWidth = (H4TechAnalyzer.GetUpperTLValue() - H4TechAnalyzer.GetLowerTLValue());
  if (selectedAction == ACTION_OPEN_BUY_ORDER){
    //reward += (Bid - H1TechAnalyzer.GetLowerTLValue()) < 0.33*h1ChannelWidth && (Bid - H1TechAnalyzer.GetLowerTLValue()) > 0 ? 10 : 0;
    //reward += (Bid - H4TechAnalyzer.GetLowerTLValue()) < 0.33*h4ChannelWidth && (Bid - H4TechAnalyzer.GetLowerTLValue()) > 0 ? 10 : 0;
    //reward += H1TechAnalyzer.GetLowerTLSlope() > 0 ? 10 : -10;
    //reward += H4TechAnalyzer.GetLowerTLSlope() > 0 ? 10 : 0;
    //reward += techAnalyzer.GetLowerTLSlope() > 0 ? 10 : 0;
    //reward += sto_Main > sto_Sig && (sto_Sig < 20 || last_sto_Sig < 20) ? 10 : 0;
    //reward += MACDMainM15 > MACDSigM15 && prevMACDMainM15 <= prevMACDSigM15 ? 10 : 0;
    //reward += MACDMainH4 < 0 ? 10 : 0;
    //reward *= exploreProb;
  }

  if (selectedAction == ACTION_OPEN_SELL_ORDER){
    //reward += (H1TechAnalyzer.GetUpperTLValue() - Ask) > 0.33*h1ChannelWidth && (H1TechAnalyzer.GetUpperTLValue() - Ask) > 0 ? 10 : 0;
    //reward += (H4TechAnalyzer.GetUpperTLValue() - Ask) > 0.33*h4ChannelWidth && (H4TechAnalyzer.GetUpperTLValue() - Ask) > 0 ? 10 : 0;
    //reward += H1TechAnalyzer.GetUpperTLSlope() < 0 ? 10 : -10;
    //reward += H4TechAnalyzer.GetUpperTLSlope() < 0 ? 10 : 0;
    //reward += techAnalyzer.GetUpperTLSlope() < 0 ? 10 : 0;
    //reward += sto_Main < sto_Sig && (sto_Sig > 80 || last_sto_Sig > 80) ? 10 : 0;
    //reward += MACDMainM15 < MACDSigM15 && prevMACDMainM15 >= prevMACDSigM15 ? 10 : 0;
    //reward += MACDMainH4 > 0 ? 10 : 0;
    //reward *= exploreProb;
  }

  if (selectedAction == ACTION_WAIT_TO_OPEN){
    //reward += (Bid - H1TechAnalyzer.GetLowerTLValue()) > 0.33*h1ChannelWidth && (H1TechAnalyzer.GetUpperTLValue() - Ask) < 0.33*h1ChannelWidth ? 10 : 0;
    //reward += (Bid - H4TechAnalyzer.GetLowerTLValue()) > 0.33*h4ChannelWidth && (H4TechAnalyzer.GetUpperTLValue() - Ask) < 0.33*h4ChannelWidth ? 10 : 0;
    //reward += sto_Main < 67 && sto_Main > 33 ? 10 : 0;
    //reward += (H1TechAnalyzer.GetUpperTLSlope() < 0 && H1TechAnalyzer.GetLowerTLSlope() > 0) || (H1TechAnalyzer.GetUpperTLSlope() > 0 && H1TechAnalyzer.GetLowerTLSlope() < 0) ? 10 : 0;
    //reward /= 2.0;
    //reward *= exploreProb;
  }

  return reward;
}

double getStrategyReward(int action = -1){
  double reward = 0;
  // ------- Indicators ------------
  datetime currentTime = iTime(NULL, 0, 0);
  double fastMA = iMA(NULL, 0, fastMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 0);
  double slowMA = iMA(NULL, 0, slowMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 0);
  //double MACDMain_0 = iMACD(NULL, 0, MACDBasePeriod / 2, MACDBasePeriod, MACDBasePeriod / 4, PRICE_CLOSE, MODE_MAIN, 0);
  //double MACDSig_0 = iMACD(NULL, 0, MACDBasePeriod / 2, MACDBasePeriod, MACDBasePeriod / 4, PRICE_CLOSE, MODE_SIGNAL, 0);
  //double MACDMain_1 = iMACD(NULL, 0, MACDBasePeriod / 2, MACDBasePeriod, MACDBasePeriod / 4, PRICE_CLOSE, MODE_MAIN, 1);
  //double MACDMain_2 = iMACD(NULL, 0, MACDBasePeriod / 2, MACDBasePeriod, MACDBasePeriod / 4, PRICE_CLOSE, MODE_MAIN, 2);
  //double MACDMain_X = iMACD(NULL, 0, MACDBasePeriod / 2, MACDBasePeriod, MACDBasePeriod / 4, PRICE_CLOSE, MODE_MAIN, 4);
  double sto_Main = iStochastic(NULL, 0, 5, 3, 3, MODE_SMA, 0, MODE_MAIN, 0);
  double sto_Sig = iStochastic(NULL, 0, 5, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 0);
  double last_sto_Main = iStochastic(NULL, 0, 5, 3, 3, MODE_SMA, 0, MODE_MAIN, 1);
  double last_sto_Sig = iStochastic(NULL, 0, 5, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 1);

  // ----- Buy order signals ----------- 
  bool buy_signal = true;

  // Signal 1: Price is above fast MA
  //buy_signal = Bid > fastMA;

  // Signal 2: Fast MA is above slow MA
  //buy_signal = buy_signal && fastMA > slowMA;

  // Signal 3: MACD is increasing
  //buy_signal = buy_signal && MACDMain_0 > MACDSig_0 && MACDMain_0 > MACDMain_X; // && MACDMain_0 - MACDMain_1 > (MACDMain_0 - MACDMain_X) / 4;

  // Signal 4: Stoch reaches a valley
  buy_signal = buy_signal && last_sto_Main < 50 && sto_Main > sto_Sig && sto_Sig > last_sto_Sig;
  reward += action == ACTION_OPEN_BUY_ORDER && buy_signal ? 10 : 0;

  // ----- Sell order signals ----------- 
  bool sell_signal = true;

  // Signal 1: Price is below fast MA
  //sell_signal = Ask < fastMA;

  // Signal 2: Fast MA is below slow MA
  //sell_signal = sell_signal && fastMA < slowMA;

  // Signal 3: MACD is decreasing
  //sell_signal = sell_signal && MACDMain_0 < MACDSig_0 && MACDMain_0 < MACDMain_X; // && MACDMain_1 - MACDMain_0 > (MACDMain_X - MACDMain_0) / 4;

  // Signal 4: Stoch reaches a peak
  sell_signal = sell_signal && last_sto_Main > 50 && sto_Main < sto_Sig && sto_Sig < last_sto_Sig;
  reward += action == ACTION_OPEN_SELL_ORDER && sell_signal ? 10 : 0;

  /*
  // Return buy or sell signal
  if (buy_signal && sell_signal)
    return ACTION_WAIT_TO_OPEN;
  else if (buy_signal)
    return ACTION_OPEN_BUY_ORDER;
  else if (sell_signal)
    return ACTION_OPEN_SELL_ORDER;
  */  
  double MACDMainM15 = iMACD(NULL, PERIOD_M15, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0);
  double MACDSigM15 = iMACD(NULL, PERIOD_M15, 12, 26, 0, PRICE_CLOSE, MODE_SIGNAL, 0);
  double MACDMainH4 = iMACD(NULL, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0);
  double MACDSigH4 = iMACD(NULL, PERIOD_H4, 12, 26, 0, PRICE_CLOSE, MODE_SIGNAL, 0);
  double MACDMainH1 = iMACD(NULL, PERIOD_H1, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0);
  double MACDSigH1 = iMACD(NULL, PERIOD_H1, 12, 26, 0, PRICE_CLOSE, MODE_SIGNAL, 0);
  if (action == ACTION_OPEN_BUY_ORDER){
    reward += MACDMainH4 > MACDSigH4 ? 2.5 : 0;
    reward += MACDMainH1 > MACDSigH1 ? 2.5 : 0;
    reward += MACDMainM15 < 0 ? 2.5 : 0;
    reward += MACDMainM15 < MACDSigM15 ? 2.5 : 0;
  }
  else if (action == ACTION_OPEN_SELL_ORDER){
    reward += MACDMainH4 < MACDSigH4 ? 2.5 : 0;
    reward += MACDMainH1 < MACDSigH1 ? 2.5 : 0;
    reward += MACDMainM15 > 0 ? 2.5 : 0;
    reward += MACDMainM15 > MACDSigM15 ? 2.5 : 0;
  }
  //if (MACDMainH4 > MACDSigH4 && MACDMainH1 > MACDSigH1 /*&& MACDMainM15 < MACDSigM15 /*&& MACDMainM15 < 0*/) reward;
  //if (MACDMainH4 < MACDSigH4 && MACDMainH1 < MACDSigH1 /*&& MACDMainM15 > MACDSigM15 /*&& MACDMainM15 > 0*/) return ACTION_OPEN_SELL_ORDER;
  return reward;
}

// Updates reward for each transition from the open ticket based on the final result of the trade
void finalizeTradeData(int ticket){
  CDataRecord *record;
  COrder order(ticket);
  bool openOrderFound = false;
  double tradeReward = 0;
  int i = trainingData.Total() - 1;
  while (i >= 0){
    record = trainingData.At(i);
    CArrayDouble *rActions = record.expectedOutput;
    if (record.ticket == ticket){
      if (rActions.At(net.getActionIndex(ACTION_OPEN_BUY_ORDER)) > 0 || rActions.At(net.getActionIndex(ACTION_OPEN_SELL_ORDER)) > 0 ){
        openOrderFound = true;
        tradeReward = ((order.GetProfit() + maxOrderProfit + minOrderProfit) + (AccountEquity() - initialBalance));
        record.reward += tradeReward;
        record.reward /= (AccountEquity() - order.GetProfit());
        record.reward /= MathMax(1, order.GetOpenBars());
        lblOpenScore.SetText("Open Score = " + DoubleToString(record.reward));
      }
      else {
        // The action was a trade management action: move stop-loss, wait, or close
        record.reward += (order.GetProfit() + maxOrderProfit + minOrderProfit) + (AccountEquity() - initialBalance);// - (maxOrderProfit - order.GetProfit());
        record.reward /= (AccountEquity() - order.GetProfit());
        record.reward /= MathMax(1, order.GetOpenBars());
        lblScore.SetText("Management score = " + DoubleToString(record.reward));
      }
    }
    else if (openOrderFound){
        
        if (rActions.At(net.getActionIndex(ACTION_WAIT_TO_OPEN)) > 0){
          if (order.GetOrderType() == OP_BUY) record.reward = -record.reward;
          record.reward += tradeReward;
          record.reward /= (AccountEquity() - order.GetProfit());
        record.reward /= MathMax(1, order.GetOpenBars());
          if (record.reward == 0) record.reward = -10;
          lblOpenScore.SetText("Wait score = " + DoubleToString(record.reward));
        }
        else {
          // Break loop once an action that isn't a wait to open action is found
          break;
        }
      }
      
    else {
      Print("Open order not found");
      break;
    }
    i--;
  }
  if (TimeCurrent() - episodeStartTime > 864000) {
    finalizeEpisodeData();
    episodeStartTime = TimeCurrent();
    initialBalance = AccountEquity();
  }
}

// Returns a datetime with the date of the previous monday at midnight
datetime getMondayBefore(datetime dt){
  MqlDateTime mdt;
  TimeToStruct(dt, mdt);
  int offset = mdt.day_of_week;
  int day_of_month = mdt.day;
  int new_day_of_month = day_of_month - offset;
  int month = mdt.mon;
  int year = mdt.year;
  if (new_day_of_month < 0){
    month -= 1;
    if (month < 0){
      month = 12 + month;
      year -= 1;
    }
    switch (month) {
      case 8:
      case 3:
      case 4:
      case 10:
        new_day_of_month = 30 + new_day_of_month;
        break;
      case 1:
        if (mdt.year % 4 == 0 && mdt.year % 1000 != 0) new_day_of_month = 29 + new_day_of_month;
        else new_day_of_month = 28 + new_day_of_month;
        break;
      default:
        new_day_of_month = 31 + new_day_of_month;
    }
  }
  // "yyyy.mm.dd hh:mi"
  string date_string = IntegerToString(mdt.year) + "." + IntegerToString(month) + "." + IntegerToString(new_day_of_month) + ".00:00";
  return StrToTime(date_string);
}

void finalizeEpisodeData(){
  if (train)
  {
    // Update final transition to represent end of episode
    CDataRecord *record = trainingData.At(trainingData.Total() - 1);   
    if (CheckPointer(record) != POINTER_INVALID){
      record.isEpisodeEnd = true;
    }
  }
}

//+------------------------------------------------------------------+
