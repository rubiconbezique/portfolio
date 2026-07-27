//+------------------------------------------------------------------+
//|                                                 TradeManager.mqh |
//|                                     Copyright 2021, Nathan Adams |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, Nathan Adams"
#property link      "https://www.mql5.com"
#property strict
//+------------------------------------------------------------------+
//| include                                                          |
//+------------------------------------------------------------------+
#include <Arrays\ArrayObj.mqh>
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class COrder : public CObject
  {
public:
                     COrder(int _ticket) { ticket = _ticket; }
   int               GetTicket() { return ticket; }
   int               GetOrderType();
   double            GetStopLoss();
   double            GetOrderLots();
   double            GetProfitLimit();
   double            GetProfit();
   double            GetOpenPrice();
   datetime          GetOpenTime();
   int               GetOpenBars(int timeframe);
   double            GetClosePrice();
   double            GetPips();
   bool              IsClosed();
   double            GetLossRisk();
private:
   int               ticket;
  };

int COrder::GetOrderType(void)
  {
   if(OrderSelect(ticket, SELECT_BY_TICKET))
      return OrderType();
   else
      return -1;
  }

double COrder::GetStopLoss(void)
  {
   if(OrderSelect(ticket, SELECT_BY_TICKET))
      return OrderStopLoss();
   else
      return 0;
  }

double COrder::GetOrderLots(){
   if(OrderSelect(ticket, SELECT_BY_TICKET))
      return OrderLots();
   else
      return 0;
}

double COrder::GetProfitLimit(void)
  {
   if(OrderSelect(ticket, SELECT_BY_TICKET))
      return OrderTakeProfit();
   else
      return 0;
  }

double COrder::GetProfit(void)
{
   if (OrderSelect(ticket, SELECT_BY_TICKET))
      return OrderProfit();
   else 
      return 0;   
}

double COrder::GetOpenPrice(void){
   if (OrderSelect(ticket, SELECT_BY_TICKET)){
      return OrderOpenPrice();
   } 
   else {
      return 0;
   }
}

datetime COrder::GetOpenTime(void){
   if (OrderSelect(ticket, SELECT_BY_TICKET)){
      return OrderOpenTime();
   } 
   else {
      return TimeCurrent();
   }
}

int COrder::GetOpenBars(int timeframe = 0){
   return iBarShift(NULL, timeframe, GetOpenTime());
}

double COrder::GetClosePrice(void){
   if (OrderSelect(ticket, SELECT_BY_TICKET)){
      return OrderClosePrice();
   } 
   else {
      return 0;
   }
}

double COrder::GetPips(void){
   if (OrderSelect(ticket, SELECT_BY_TICKET)){
      double open = OrderOpenPrice();
      double last = OrderCloseTime() > 0 ? OrderClosePrice() : (OrderType() == OP_BUY ? Bid : Ask);
      return OrderType() == OP_BUY ? (last - open) / Point : (open - last) / Point;
   } 
   else {
      return 0;
   }
   
}

bool COrder::IsClosed(){
   if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
   {
      return OrderCloseTime() != 0;
   }     
   return false; 
}

double COrder::GetLossRisk(){
   double risk = 0;
   if(OrderSelect(ticket, SELECT_BY_TICKET) && !IsClosed()){
      double lots = OrderLots();
      risk = OrderType() == OP_BUY ? (OrderStopLoss() - Bid) / Point * lots : (Ask - OrderStopLoss()) / Point * lots;
   }
   //Print("Order " + IntegerToString(ticket) + " loss risk = " + DoubleToString(risk));
   return risk;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class COrderManager
  {
public:
                     COrderManager();
                    ~COrderManager() { };
   void              OrderAccounting();
   bool              OpenBuyOrder(double lots, double stopLossPoints, double profitLimitPoints);
   bool              OpenSellOrder(double lots, double stopLossPoints, double profitLimitPoints);
   bool              ModifyStopLoss(double stop, int index = 0);
   bool              ModifyStopLossByTicket(double stop, int ticket);
   bool              MoveTrailingStop(double stop, int index = 0, bool onlyIfPastOpen = true);
   bool              MoveTrailingStop(double stop, COrder *&order, bool onlyIfPastOpen = true);
   bool              MoveTrailingStopByTicket(double stop, int ticket, bool onlyIfPastOpen = true);
   bool              CloseOrder(int index = 0);
   bool              CloseOrderByTicket(int ticket);
   void              CloseAllBuyOrders();
   void              CloseAllSellOrders();
   int               OpenOrderCount() { return orders.Total(); }
   COrder            *GetOrder(int index = 0);
   bool              IsOrderClosed(int index = 0);
   bool              IsOrderClosed(COrder *order);
   bool              IsOrderClosedByTicket(int ticket);
   double            CalcLotsFromRisk(double stopLoss, double lossRisk, double percentOfEquity);
   double            GetWinRatio(int histLength = 0);
   double            GetProfitRatio();
   double            GetAvgProfit(int histLength = 0);
   double            GetAvgPips();
   double            GetTradeCapital() { return AccountEquity() - savings; }
   double            GetFreeTradeCapital() { return MathMax(0, AccountFreeMargin() - savings); }
   void              bank(double amount) { /*savings += amount;*/ }
   double            GetSavings() { return savings; }
   double            GetAvgTradeFreq(int count);
   datetime          GetLastTradeCloseTime();
   int               GetBarsSinceLastTrade();
private:
   CArrayObj         orders;
   int               checkError(int error);
   double            savings;
   double            minTradeCapital;
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
COrderManager::COrderManager(){
   minTradeCapital = AccountEquity();
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void COrderManager::OrderAccounting(void)
  {
   int orderCount = 0;
   for(int i = 1; i <= OrdersTotal(); i++)          // Loop through orders
     {
      if(OrderSelect(i - 1, SELECT_BY_POS) == true)  // If there is the next one
        {
         // Analyzing orders:
         if(OrderSymbol() != Symbol())
            continue;      // Another security
         if(OrderType() > 1)                      // Pending order found
           {
            Alert("Pending order detected. EA doesn't work.");
            return;                             // Exit start()
           }
         orderCount++;
        }
     }

   if(orderCount != orders.Total())
     {
      // TODO: Implement order event listener service

      // Add profit to savings
      if (GetTradeCapital() > minTradeCapital) bank(GetTradeCapital() - minTradeCapital);
     }

   orders.Clear();
   for(int i = 1; i <= OrdersTotal(); i++)          // Loop through orders
     {
      if(OrderSelect(i - 1, SELECT_BY_POS) == true)  // If there is the next one
        {
         // Analyzing orders:
         if(OrderSymbol() != Symbol())
            continue;      // Another security
         if(OrderType() > 1)                      // Pending order found
           {
            Alert("Pending order detected. EA doesn't work.");
            return;                             // Exit start()
           }
         orders.Add(new COrder(OrderTicket()));
        }
     }

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool COrderManager::OpenBuyOrder(double lots,double stopLossPoints,double profitLimitPoints)
  {
   int error = -1;
   int ticket;
   do
     {
      RefreshRates();                        // Refresh rates
      double Min_Stop = MarketInfo(NULL, MODE_STOPLEVEL);
      double One_Lot= MarketInfo(NULL,MODE_MARGINREQUIRED);
      stopLossPoints = MathMax(stopLossPoints, Min_Stop);
      double SL = Bid - stopLossPoints*Point;     // Calculating SL of opened
      double TP = Bid + MathMax(profitLimitPoints, Min_Stop)*Point;   // Calculating TP of opened

      ticket = OrderSend(NULL,OP_BUY,lots,Ask,3,SL,TP);//Opening Buy
      if(ticket > 0)                         // Success :)
        {
         Alert("Opened order Buy ",ticket, " for $", lots * One_Lot);
         orders.Add(new COrder(ticket));
         return(true);                             // Exit start()
        }

      error = checkError(GetLastError());
     }
   while(error == 1);         // Processing errors
   return false;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool COrderManager::OpenSellOrder(double lots,double stopLossPoints,double profitLimitPoints)
  {
   int error = -1;
   int ticket;
   do
     {
      RefreshRates();                        // Refresh rates
      double Min_Stop = MarketInfo(NULL, MODE_STOPLEVEL);
      double One_Lot= MarketInfo(NULL,MODE_MARGINREQUIRED);
      stopLossPoints = MathMax(stopLossPoints, Min_Stop);
      double SL = Ask + stopLossPoints*Point;     // Calculating SL of opened
      double TP = Ask - MathMax(profitLimitPoints, Min_Stop)*Point;   // Calculating TP of opened

      ticket = OrderSend(NULL,OP_SELL,lots,Bid,3,SL,TP);//Opening Buy
      if(ticket > 0)                         // Success :)
        {
         Alert("Opened order Sell ",ticket, " for $", lots * One_Lot);
         orders.Add(new COrder(ticket));
         return(true);                             // Exit start()
        }

      error = checkError(GetLastError());
     }
   while(error == 1);         // Processing errors
   return false;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool COrderManager::ModifyStopLoss(double stop, int index=0)
  {
   COrder *order = orders.At(index);
   if(CheckPointer(order) == POINTER_INVALID)
      return false;
   return ModifyStopLossByTicket(stop, order.GetTicket());
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool COrderManager::ModifyStopLossByTicket(double stop, int ticket)
  {
   if(OrderSelect(ticket, SELECT_BY_TICKET) && stop >= MarketInfo(NULL, MODE_STOPLEVEL))
     {
      int error = -1;
      do
        {
         RefreshRates();
         if(OrderType() == ORDER_TYPE_BUY)
           {
            if(OrderModify(OrderTicket(), OrderOpenPrice(), NormalizeDouble(Bid - stop*Point, Digits), OrderTakeProfit(), 0))
               return true;
           }
         else
            if(OrderType() == ORDER_TYPE_SELL)
              {
               if(OrderModify(OrderTicket(), OrderOpenPrice(), NormalizeDouble(Ask + stop*Point, Digits), OrderTakeProfit(), 0))
                  return true;
              }
         error = checkError(GetLastError());
        }
      while(error == 1);
     }
   return false;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool COrderManager::MoveTrailingStop(double stop,int index=0,bool onlyIfPastOpen=true)
{
   COrder *order = orders.At(index);
   if(CheckPointer(order) == POINTER_INVALID)
      return false;
   return MoveTrailingStopByTicket(stop, order.GetTicket(), onlyIfPastOpen);   
}  
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool COrderManager::MoveTrailingStop(double stop,COrder *&order,bool onlyIfPastOpen=true)
{
   if (CheckPointer(order) == POINTER_INVALID)
      return false;
   return MoveTrailingStopByTicket(stop, order.GetTicket(), onlyIfPastOpen);
      
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool COrderManager::MoveTrailingStopByTicket(double stop,int ticket, bool onlyIfPastOpen = true)
  {
   if(OrderSelect(ticket, SELECT_BY_TICKET))
     {
      if(OrderType() == ORDER_TYPE_BUY
         && (Bid - OrderOpenPrice() > NormalizeDouble(stop*Point, Digits) || !onlyIfPastOpen)
         && Bid - Point*stop - OrderStopLoss() > Point
         && Bid - stop*Point < OrderTakeProfit())
         return ModifyStopLossByTicket(stop, ticket);
      else
         if(OrderType() == ORDER_TYPE_SELL
            && (OrderOpenPrice() - Ask > NormalizeDouble(stop*Point, Digits) || !onlyIfPastOpen)
            && OrderStopLoss() - (Ask + Point*stop) > Point
            && Ask + stop*Point > OrderTakeProfit())
            return ModifyStopLossByTicket(stop, ticket);
     }
   return false;

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool COrderManager::CloseOrder(int index=0)
  {
   COrder *order = orders.At(index);
   if(CheckPointer(order) == POINTER_INVALID)
      return false;
   return CloseOrderByTicket(order.GetTicket());
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool COrderManager::CloseOrderByTicket(int ticket)
  {
   bool Ans  = false;                     // Server response after closing
   int error = -1;
   do
     {
      if(!OrderSelect(ticket, SELECT_BY_TICKET))
        {
         if(checkError(GetLastError()) == 1)
            continue;
         else
            return false;
        }
      double price = (OrderType() == 0 ? Bid : Ask);
      double lot = OrderLots();
      RefreshRates();                        // Refresh rates
      Ans = OrderClose(ticket,lot,price,2);      // Closing order
      if(Ans == true)                            // Success :)
        {
         Alert("Closed order Buy ",ticket);
         int index = -1;
         for(int i = 0; i < orders.Total(); i++)
           {
            COrder *order = orders.At(i);
            if(order.GetTicket() == ticket)
               index  = i;
           }
         if(index > -1)
            orders.Delete(index);
         return(true);                              // Exit closing loop
        }
      error = checkError(GetLastError());
     }
   while(error == 1);
   return false;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void COrderManager::CloseAllBuyOrders(void)
{
   for (int i = 0; i < orders.Total(); i++)
   {
      COrder *order = orders.At(i);
      if (CheckPointer(order) != POINTER_INVALID && order.GetOrderType() == ORDER_TYPE_BUY)
         CloseOrderByTicket(order.GetTicket());
   }
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void COrderManager::CloseAllSellOrders(void)
{
   for (int i = 0; i < orders.Total(); i++)
   {
      COrder *order = orders.At(i);
      if (CheckPointer(order) != POINTER_INVALID && order.GetOrderType() == ORDER_TYPE_SELL)
         CloseOrderByTicket(order.GetTicket());
   }
}  
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
COrder *COrderManager::GetOrder(int index=0)
  {
   if(index < orders.Total())
     {
      COrder *order = orders.At(index);
      return order;
     }
   else
      return NULL;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double COrderManager::CalcLotsFromRisk(double stop,double lossRisk,double percentOfEquity)
  {
   double Min_Lot = MarketInfo(NULL,MODE_MINLOT);
   double Free = GetFreeTradeCapital();
   double One_Lot= MarketInfo(NULL,MODE_MARGINREQUIRED);
   double Step = MarketInfo(NULL,MODE_LOTSTEP);
   stop = MathMax(stop, MarketInfo(NULL, MODE_STOPLEVEL));
   double Lts = MathFloor(lossRisk * Free / stop / Step) * Step;
   double marginReq = MarketInfo(NULL, MODE_MARGINREQUIRED);
   double equity = GetTradeCapital();
   if(marginReq * Lts + Lts * stop > percentOfEquity * equity)
     {
      Lts = MathFloor(percentOfEquity * equity / (marginReq + stop) / Step) * Step;
     }
   if(marginReq * Lts + Lts * stop > Free)
     {
      Lts = MathFloor(Free / (marginReq + stop) / Step) * Step;
     }
   if (Lts > 1)
   {
      Print("Stop = ", stop);
      Print("Lts = ", Lts);
      Print("Free = ", Free);
      Print("marginReq = ", marginReq);
   }  
   if(Lts < Min_Lot)
      Lts = Min_Lot;               // Not less than minimal
   if(Lts*One_Lot > percentOfEquity * Free)                        // Lot larger than free margin
     {
      Alert(" Not enough money for ", Lts," lots");
      return -1;                                   // Exit
     }
   return Lts;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool COrderManager::IsOrderClosedByTicket(int ticket)
{
   if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
   {
      return OrderCloseTime() != 0;
   }     
   return false;    
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool COrderManager::IsOrderClosed(int index=0)
{
   COrder *order = GetOrder(index);
   return IsOrderClosedByTicket(order.GetTicket());
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool COrderManager::IsOrderClosed(COrder *order)
{
   return IsOrderClosedByTicket(order.GetTicket());
}  
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int COrderManager::checkError(int error)
  {
   switch(error)
     {
      // Not crucial errors
      case  4:
         Alert("Trade server is busy. Trying once again..");
         Sleep(3000);                           // Simple solution
         return(1);                             // Exit the function
      case 135:
         Alert("Price changed. Trying once again..");
         RefreshRates();                        // Refresh rates
         return(1);                             // Exit the function
      case 136:
         Alert("No prices. Waiting for a new tick..");
         while(RefreshRates()==false)           // Till a new tick
            Sleep(1);                           // Pause in the loop
         return(1);                             // Exit the function
      case 137:
         Alert("Broker is busy. Trying once again..");
         Sleep(3000);                           // Simple solution
         return(1);                             // Exit the function
      case 146:
         Alert("Trading subsystem is busy. Trying once again..");
         Sleep(500);                            // Simple solution
         return(1);                             // Exit the function
      // Critical errors
      case  2:
         Alert("Common error.");
         return(0);                             // Exit the function
      case  5:
         Alert("Old terminal version.");
         return(0);                             // Exit the function
      case 64:
         Alert("Account blocked.");
         return(0);                             // Exit the function
      case 133:
         Alert("Trading forbidden.");
         return(0);                             // Exit the function
      case 134:
         Alert("Not enough money to execute operation.");
         return(0);                             // Exit the function
      case 9000:
         //Alert("Stop too small");
         return(2);
      default:
         Alert("Error occurred: ",error);  // Other variants
         return(0);                             // Exit the function
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double COrderManager::GetWinRatio(int histLength = 0){
   double wins = 0;
   histLength = histLength <=0 ? OrdersHistoryTotal() : histLength;
   for (int i = 0; i < histLength && i < OrdersHistoryTotal(); i++){
      if (OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)){
         if (OrderProfit() > 0){
            wins++;
         }
      }
   }
   return OrdersHistoryTotal() > 0 ? wins / OrdersHistoryTotal() : 0;
}
double COrderManager::GetProfitRatio(){
   double profit = 0, loss = 0;
   for (int i = 0; i < OrdersHistoryTotal(); i++){
      if (OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)){
         if (OrderProfit() > 0){
            profit += OrderProfit();
         }
         else {
            loss += MathAbs(OrderProfit());
         }
      }
   }
   
   if (profit > 0 && loss > 0){
      return profit / loss;
   }
   else if (profit > 0){
      return 1000;
   }
   else if (loss > 0) {
      return 1.0/1000;
   }
   else {
      return 1.0;
   }
}
double COrderManager::GetAvgProfit(int histLength = 0){
   double profit = 0;
   histLength = histLength <=0 ? OrdersHistoryTotal() : histLength;
   for (int i = 0; i < histLength && i < OrdersHistoryTotal(); i++){
      if (OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)){
         profit += OrderProfit();
      }
   }
   return OrdersHistoryTotal() > 0 ? profit / OrdersHistoryTotal() : 0;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double COrderManager::GetAvgPips(){
   double total = 0;
   int count = 0;
   for (int i = 0; i < OrdersHistoryTotal(); i++){
      if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)){
         COrder order(OrderTicket());
         if (order.GetPips() > 0){
            total += order.GetPips();
            count++;
         }
      }
   }
   return count > 0 ? total / count : 0.0;
}

double COrderManager::GetAvgTradeFreq(int count){
   count = MathMin(OrdersHistoryTotal(), count);
   if (count <= 0) return 0.0;
   if (OrderSelect(OrdersHistoryTotal() - count, SELECT_BY_POS, MODE_HISTORY)){
      int minElapsed = (int)TimeCurrent() / 60 - (int)OrderCloseTime() / 60;
      return minElapsed > 0 ? (double)count / minElapsed : 0;
   }
   return 0.0;
}

datetime COrderManager::GetLastTradeCloseTime(){
   if (OrderSelect(OrdersHistoryTotal() - 1, SELECT_BY_POS, MODE_HISTORY)){
      return OrderCloseTime();
   }
   return 0;
}

int COrderManager::GetBarsSinceLastTrade(){
   if (OrderSelect(OrdersHistoryTotal() - 1, SELECT_BY_POS, MODE_HISTORY))
      return iBarShift(NULL, 0, OrderCloseTime());
   else
      return 0;
}
//+------------------------------------------------------------------+
