//+------------------------------------------------------------------+
//|                                            TechnicalAnalysis.mqh |
//|                                     Copyright 2022, Nathan Adams |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2022, Nathan Adams"
#property link      "https://www.mql5.com"
#property strict
//+------------------------------------------------------------------+
//| include                                                          |
//+------------------------------------------------------------------+
#include <Arrays\ArrayObj.mqh>
#include <Arrays\ArrayDouble.mqh>
#include <Arrays\ArrayInt.mqh>
#include <UITools.mqh>
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CTechAnalyzer : public CObject {
  public:
    // Constructors and destructors
    CTechAnalyzer(int _timePeriod = 0, color _clr = clrRed);
    ~CTechAnalyzer();
    
    // Public methods
    void DrawUpperTrendLine(int start, int end, int window, int stride, int maxCritVals, bool markPoints = false);
    void DrawLowerTrendLine(int start, int end, int window, int stride, int maxCritVals, bool markPoints = false);
    double GetUpperTLValue(int index = 0) { return upperA + upperB*index; };
    double GetUpperTLSlope() { return upperB; }
    void GetUpperTLFitParams(CArrayDouble *&result);
    double GetLowerTLValue(int index = 0) { return lowerA + lowerB*index; };
    double GetLowerTLSlope() { return lowerB; }
    void GetLowerTLFitParams(CArrayDouble *&result);
    void DrawResistanceLine(int start, int end);
    void DrawSupportLine(int start, int end);
    double GetResistancePrice(int start, int end);
    double GetSupportPrice(int start, int end);
    double GetResistanceIndex(int start, int end);
    double GetSupportIndex(int start, int end);
  
  private:
    CArrayObj upperChartObjects, lowerChartObjects;
    CArrayDouble *upperPrices, *lowerPrices;
    CArrayInt *upperIndices, *lowerIndices;
    int timePeriod;
    color clr;
    double upperA, upperB, upperR;
    double lowerA, lowerB, lowerR;

    CHLine *resLine, *supLine;

    void LSFitLinear(CArrayInt *&x_vals, CArrayDouble *&y_vals, CArrayDouble *&result);

};

CTechAnalyzer::CTechAnalyzer(int _timePeriod = 0, color _clr = clrRed){
  timePeriod = _timePeriod;
  clr = _clr;
}

CTechAnalyzer::~CTechAnalyzer(){
  if (CheckPointer(upperPrices) != POINTER_INVALID) delete upperPrices;
  if (CheckPointer(lowerPrices) != POINTER_INVALID) delete lowerPrices;
  if (CheckPointer(upperIndices) != POINTER_INVALID) delete upperIndices;
  if (CheckPointer(lowerIndices) != POINTER_INVALID) delete lowerIndices;
  if (CheckPointer(resLine) != POINTER_INVALID) delete resLine;
  if (CheckPointer(supLine) != POINTER_INVALID) delete supLine;
}

void CTechAnalyzer::DrawUpperTrendLine(int start, int end, int window, int stride, int maxCritVals, bool markPoints = true){
  CArrayDouble *prices, *newPrices, *finalPrices;
  CArrayInt *indices, *newIndices, *finalIndices;
  prices = new CArrayDouble();
  newPrices = new CArrayDouble();
  finalPrices = new CArrayDouble();
  indices = new CArrayInt();
  newIndices = new CArrayInt();
  finalIndices = new CArrayInt();

  // Split the range into sections
  for (int n = 0; n < 2; n++){
    // Fill starting arrays with price and index data
    for (int i = start; i < end; i++){
      prices.Add(iHigh(NULL, timePeriod, i));
      indices.Add(i);
    }

    do {
      newPrices.Clear();
      newIndices.Clear();
      /*while (window + stride > prices.Total() && stride > 1){
        stride -= 1;
      }*/
      //Print("prices.Total() = ", prices.Total());
      for (int i = 0; i < prices.Total(); i += stride){
        double max = prices.At(i);
        int maxIndex = indices.At(i);
        for (int j = i + 1; j < i + window && j < prices.Total(); j++){
          double val = prices.At(j);
          if (val > max){
            max = val;
            maxIndex = indices.At(j);
          }
        }
        newPrices.Add(max);
        newIndices.Add(maxIndex);
      }

      if (prices.Total() > maxCritVals){
        prices.Clear();
        indices.Clear();
      }
      prices.AssignArray(newPrices);
      indices.AssignArray(newIndices);
    } while (prices.Total() > maxCritVals);

    // Save final points for each section
    finalPrices.AddArray(prices);
    finalIndices.AddArray(indices);
  }
  // Store final prices and final indices in prices and indices array to avoid refactoring code below
  prices.Clear();
  prices.AssignArray(finalPrices);
  indices.Clear();
  indices.AssignArray(finalIndices);

  // Create chart objects
  // Mark highs
  upperChartObjects.Clear();
  if (markPoints){
    for (int i = 0; i < prices.Total(); i++){
      datetime t = iTime(NULL, timePeriod, indices.At(i));
      upperChartObjects.Add(new CArrowDown("Down Arrow " + IntegerToString(timePeriod) + IntegerToString(upperChartObjects.Total()), t, prices.At(i), clr));
      //Print("Added Arrow ", timePeriod, i);
    }
  }
  // Calculate best fit line
  CArrayDouble *result = new CArrayDouble();
  LSFitLinear(indices, prices, result);
  double a = result.At(0);
  double b = result.At(1);
  double r = result.At(2);
  upperA = a;
  upperB = b;
  upperR = r;

  //Print("r-value"  + IntegerToString(timePeriod) + " = ", r);

  // Adjust
  for (int i = 0; i < indices.Total(); i++){
    double y = a + b*indices.At(i);
    if (y < prices.At(i)){
      a = prices.At(i) - b*indices.At(i);
    }
  }

  // Draw trendline
  datetime t1 = iTime(NULL, timePeriod, indices.At(indices.Total() - 1));
  double price1 = a + b * indices.At(indices.Total() - 1);
  datetime t2 = iTime(NULL, timePeriod, indices.At(0));
  double price2 = a + b * indices.At(0);

  upperChartObjects.Add(new CTrendLine("Trendline " + IntegerToString(timePeriod), t1, price1, t2, price2, clr));

  // Save values
  if (CheckPointer(upperPrices) == POINTER_INVALID) upperPrices = new CArrayDouble();
  upperPrices.Clear();
  upperPrices.AssignArray(prices);
  if (CheckPointer(upperIndices) == POINTER_INVALID) upperIndices = new CArrayInt();
  upperIndices.Clear();
  upperIndices.AssignArray(indices);

  // Clean up
  delete prices;
  delete newPrices;
  delete indices;
  delete newIndices;
  delete result;
}

void CTechAnalyzer::DrawLowerTrendLine(int start, int end, int window, int stride, int maxCritVals, bool markPoints = false){
  CArrayDouble *prices, *newPrices;
  CArrayInt *indices, *newIndices;
  prices = new CArrayDouble();
  newPrices = new CArrayDouble();
  indices = new CArrayInt();
  newIndices = new CArrayInt();


  // Fill starting arrays with price and index data
  for (int i = start; i < end; i++){
    prices.Add(iLow(NULL, timePeriod, i));
    indices.Add(i);
  }

  do {
    newPrices.Clear();
    newIndices.Clear();
    /*while (window + stride > prices.Total() && stride > 1){
      stride -= 1;
    }*/
    //Print("prices.Total() = ", prices.Total());
    for (int i = 0; i < prices.Total(); i += stride){
      double min = prices.At(i);
      int minIndex = indices.At(i);
      for (int j = i + 1; j < i + window && j < prices.Total(); j++){
        double val = prices.At(j);
        if (val < min){
          min = val;
          minIndex = indices.At(j);
        }
      }
      newPrices.Add(min);
      newIndices.Add(minIndex);
    }

    if (prices.Total() > maxCritVals){
      prices.Clear();
      indices.Clear();
    }
    prices.AssignArray(newPrices);
    indices.AssignArray(newIndices);
  } while (prices.Total() > maxCritVals);

  // Mark lows
  lowerChartObjects.Clear();
  if (markPoints){
    for (int i = 0; i < prices.Total(); i++){
      datetime t = iTime(NULL, timePeriod, indices.At(i));
      lowerChartObjects.Add(new CArrowUp("Up Arrow " + IntegerToString(timePeriod) + IntegerToString(lowerChartObjects.Total()), t, prices.At(i), clr));
      //Print("Added Arrow ", timePeriod, i);
    }
  }

  // Calculate best fit line
  CArrayDouble *result = new CArrayDouble();
  LSFitLinear(indices, prices, result);
  double a = result.At(0);
  double b = result.At(1);
  double r = result.At(2);
  lowerA = a;
  lowerB = b;
  lowerR = r;

  // If r-value is low, try removing points and recalculating
  /*if (r < 0.98){
    CArrayInt *x_vals = new CArrayInt();
    CArrayDouble *y_vals = new CArrayDouble();
    for (int i = 0; i < indices.Total(); i++){
      x_vals.Clear();
      y_vals.Clear();
      x_vals.AssignArray(indices);
      y_vals.AssignArray(prices);
      x_vals.Delete(i);
      y_vals.Delete(i);
      result.Clear();
      LSFitLinear(x_vals, y_vals, result);
      if (result.At(2) > r){
        a = result.At(0);
        b = result.At(1);
        r = result.At(2);
      }
    }
    delete x_vals;
    delete y_vals;
  }  */
  //Print("r-value"  + IntegerToString(timePeriod) + " = ", r);
  
  // Adjust
  for (int i = 0; i < indices.Total(); i++){
    double y = a + b*indices.At(i);
    if (y > prices.At(i)){
      a = prices.At(i) - b*indices.At(i);
    }
  }

  // Draw trendline
  datetime t1 = iTime(NULL, timePeriod, indices.At(indices.Total() - 1));
  double price1 = a + b * indices.At(indices.Total() - 1);
  datetime t2 = iTime(NULL, timePeriod, indices.At(0));
  double price2 = a + b * indices.At(0);

  lowerChartObjects.Add(new CTrendLine("Lower Trendline " + IntegerToString(timePeriod), t1, price1, t2, price2, clr));

  // Save values
  if (CheckPointer(lowerPrices) == POINTER_INVALID) lowerPrices = new CArrayDouble();
  lowerPrices.Clear();
  lowerPrices.AssignArray(prices);
  if (CheckPointer(lowerIndices) == POINTER_INVALID) lowerIndices = new CArrayInt();
  lowerIndices.Clear();
  lowerIndices.AssignArray(indices);

  // Clean up
  delete prices;
  delete newPrices;
  delete indices;
  delete newIndices;
  delete result;
}

void CTechAnalyzer::GetUpperTLFitParams(CArrayDouble *&result){
  result.Clear();
  result.Add(upperA);
  result.Add(upperB);
  result.Add(upperR);
}

void CTechAnalyzer::GetLowerTLFitParams(CArrayDouble *&result){
  result.Clear();
  result.Add(lowerA);
  result.Add(lowerB);
  result.Add(lowerR);
}

void CTechAnalyzer::LSFitLinear(CArrayInt *&x_vals, CArrayDouble *&y_vals, CArrayDouble *&result){
  double a = 0, b = 0, r = 0;
  double xAvg = 0, yAvg = 0;
  double numer = 0, denom = 1;

  // Find averages
  for (int i = 0; i < x_vals.Total(); i++){
    xAvg += x_vals.At(i);
    yAvg += y_vals.At(i);
  }
  xAvg /= (double)x_vals.Total();
  yAvg /= y_vals.Total();

  // Calculate differences
  for (int i = 0; i < x_vals.Total(); i++){
    numer += (x_vals.At(i) - xAvg) * (y_vals.At(i) - yAvg);
    denom += (x_vals.At(i) - xAvg) * (x_vals.At(i) - xAvg);
  }

  // Calculate intercept and slope
  b = numer / denom;
  a = yAvg - b * xAvg;

  // Calulcate residual sum of squares
  double rss = 0, tss = 0;;
  for (int i = 0; i < y_vals.Total(); i++){
    rss += (y_vals.At(i) - (a + b * x_vals.At(i))) * (y_vals.At(i) - (a + b * x_vals.At(i)));
    tss += (y_vals.At(i) - yAvg) * (y_vals.At(i) - yAvg);
  }
  r = tss > 0 ? MathSqrt(1 - rss/tss) : 0;

  result.Clear();
  result.Add(a);
  result.Add(b);
  result.Add(r);

}

double CTechAnalyzer::GetResistanceIndex(int start, int end){
  return iHighest(NULL, timePeriod, MODE_HIGH, end, start);
}

double CTechAnalyzer::GetResistancePrice(int start, int end){
  int index = iHighest(NULL, timePeriod, MODE_HIGH, end, start);
  return iHigh(NULL, timePeriod, index);
}

void CTechAnalyzer::DrawResistanceLine(int start, int end){
  if (CheckPointer(resLine) != POINTER_INVALID) delete resLine;
  resLine = new CHLine("Resistance" + IntegerToString(timePeriod), GetResistancePrice(start, end), clr);
}

double CTechAnalyzer::GetSupportIndex(int start, int end){
  return iLowest(NULL, timePeriod, MODE_HIGH, end, start);
}

double CTechAnalyzer::GetSupportPrice(int start, int end){
  int index = iLowest(NULL, timePeriod, MODE_HIGH, end, start);
  return iLow(NULL, timePeriod, index);
}

void CTechAnalyzer::DrawSupportLine(int start, int end){
  if (CheckPointer(supLine) != POINTER_INVALID) delete supLine;
  supLine = new CHLine("Support" + IntegerToString(timePeriod), GetSupportPrice(start, end), clr);
}
