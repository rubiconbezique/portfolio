//+------------------------------------------------------------------+
//|                                                   ANeuralNet.mqh |
//|                                     Copyright 2019, Nathan Adams |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2019, Nathan Adams"
#property link      "https://www.mql5.com"
#property strict
//+------------------------------------------------------------------+
//| include                                                          |
//+------------------------------------------------------------------+
#include <Arrays\ArrayDouble.mqh>
#include <Arrays\ArrayInt.mqh>
#include <Arrays\ArrayObj.mqh>
#include <Math\Alglib\bitconvert.mqh>
#include <DataManager.mqh>
#include <stdlib.mqh>
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
const int CNEURON_BASE = 1001;
const int CNEURON = 1002;
const int CNEURON_NET = 1003;
const int CNEURON_IDENT = 1004;
static int CNEURON_BASIS = 1005;
enum activation_functions {TANH, LINEAR, RELU, LEAKY_RELU};
//+------------------------------------------------------------------+
//| class CConnection                                                |
//+------------------------------------------------------------------+
class CConnection : public CObject
  {
public:
   double            weight;
   double            deltaWeight;
                     CConnection() {};
                     CConnection(double w, double dW = 0.0) { weight=w; deltaWeight=dW; }
                    ~CConnection() {};
   //--- methods for working with files
   virtual bool      Save(const int file_handle);
   virtual bool      Load(const int file_handle);
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CConnection::Save(const int file_handle)
  {
   if(file_handle==INVALID_HANDLE)
      return false;
//---
   if(FileWriteDouble(file_handle,weight)<=0)
      return false;
   if(FileWriteDouble(file_handle,deltaWeight)<=0)
      return false;
//---
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CConnection::Load(const int file_handle)
  {
   if(file_handle==INVALID_HANDLE)
      return false;
//---
   weight=FileReadDouble(file_handle);
   deltaWeight=FileReadDouble(file_handle);
//---
   return true;
  }
//+------------------------------------------------------------------+
//| class CArrayCon                                                  |
//+------------------------------------------------------------------+
class CArrayCon  :    public CArrayObj
  {
public:
                     CArrayCon(void) {};
                    ~CArrayCon(void) {};
   //---
   virtual bool      CreateElement(const int index);
   virtual int       Type(void) const { return(0x7781); }
   bool              Save(const int file_handle);
   bool              Load(const int file_handle);
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CArrayCon::CreateElement(const int index)
  {
   if(index<0)
      return false;
//---
   if(m_data_max<index+1)
     {
      if(ArrayResize(m_data,index+10)<=0)
         return false;
      m_data_max=ArraySize(m_data);
     }
//---
   m_data[index]=new CConnection((MathRand()+1)/32768.0);
   if(!CheckPointer(m_data[index])!=POINTER_INVALID)
      return false;
//m_data_total=MathMax(m_data_total,index);
   m_data_total++;
//---
   return (true);
  }

bool CArrayCon::Save(const int file_handle){
  if(file_handle==INVALID_HANDLE)
      return false;
  if (!FileWriteInteger(file_handle, Total())) return false;
  bool result = true;
  for (int i = 0; i < Total(); i++){
    CConnection *c = At(i);
    result = result && c.Save(file_handle);
  }
  return result;
}

bool CArrayCon::Load(const int file_handle){
  if(file_handle==INVALID_HANDLE)
      return false;
  Clear();
  int total = FileReadInteger(file_handle);
  for (int i = 0; i < total; i++){
    CConnection *c = new CConnection();
    c.Load(file_handle);
    Add(c);
  }
  return true;
}

//+------------------------------------------------------------------+
//| class CNeuronBase - base class for all neuron types              |
//+------------------------------------------------------------------+
class CNeuronBase    :  public CObject
  {
protected:
   double            eta; // Learning rate
   double            alpha;  // Momentum
   double            outputVal;
   uint              myIndex;
   double            gradient;
   //---
   virtual double    activationFunction(double x)                 {  return 1.0;       }
   virtual double    activationFunctionDerivative(double x)       {  return 1.0;       }
   virtual CArrayObj *getOutputLayer(void)                        {  return NULL;      }
public:
                     CNeuronBase(void) {Connections = new CArrayCon();};
                    ~CNeuronBase(void) { delete Connections; };
   CArrayCon         *Connections;
   virtual bool      Init(uint numInputs, uint myIndex);
   //---
   virtual void      setOutputVal(double val)                     {  outputVal=val;    }
   virtual double    getOutputVal()                               {  return outputVal; }
   virtual void      setGradient(double val)                      {  gradient=val;     }
   virtual double    getGradient()                                {  return gradient;  }
   //---
   virtual bool      feedForward(CObject *&SourceObject);
   virtual bool      calcHiddenGradients(CObject *&TargetObject);
   virtual bool      updateInputWeights(CObject *&SourceObject);
   //---
   void              setLearningRate(double rate) { eta = rate; };
   void              setMomentum(double m) { alpha = m; };
   //---
   virtual bool      Save(int const file_handle)                  {  return(Connections.Save(file_handle)); }
   virtual bool      Load(int const file_handle)                  {  return(Connections.Load(file_handle)); }
   //---
   virtual int       Type(void)        const                       {  return CNEURON_BASE;                  }
  };
//+------------------------------------------------------------------+
//| class CNeuron                                                    |
//+------------------------------------------------------------------+
class CNeuron  :  public CNeuronBase
  {
public:
                     CNeuron() { myIndex = 0; }
                     CNeuron(uint numInputs,uint index, int activation_type = 0);
   virtual bool      feedForward(const CArrayObj *&prevLayer);
   virtual void      calcOutputGradients(double targetVals);
   virtual bool      calcHiddenGradients(const CArrayObj *&nextLayer);
   virtual bool      updateInputWeights(CArrayObj *&prevLayer);
   virtual int       Type()   const { return CNEURON; }
   virtual bool      Save(int const file_handle);
   virtual bool      Load(int const file_handle);

protected:
   int activationType;
   void              setActivationType(int type) { activationType = type; }
   double            tanH(double x);
   double            dTanH(double x);
   double            identFunc(double x);
   double            dIdentFunc(double x);
   double            ReLU(double x);
   double            dReLU(double x);
   double            LeakyReLU(double x);
   double            dLeakyReLU(double x);
   static double     randomWeight() { return(double)MathRand()/32767.0; }
   double            activationFunction(double x);
   double            activationFunctionDerivative(double x);
   double            sumWeightedDerivOfError(const CArrayObj *&nextLayer) const;
   double            gradientSum;
   double            count;
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
CNeuron::CNeuron(uint numInputs, uint index, int activation_type = 0)
  {
   eta = 0.0001;
   alpha = 0.95;
   gradientSum = 0;
   count = 0;
   activationType = activation_type;
   Connections = new CArrayCon();
   for(uint c = 0; c < numInputs; c++)
     {
      Connections.CreateElement(c);
     }

   myIndex = index;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CNeuron::activationFunction(double x)
  {
    switch (activationType){
      case 0:
        return tanH(x);
      case 1:
        return identFunc(x);
      case 2:
        return ReLU(x);
      case 3:
        return LeakyReLU(x);
      case 1005:
        return 1.0;
    }
    return tanH(x);
  }

double CNeuron::activationFunctionDerivative(double x)
  {
    switch (activationType){
      case 0:
        return dTanH(x);
      case 1:
        return dIdentFunc(x);
      case 2:
        return dReLU(x);
      case 3:
        return dLeakyReLU(x);
      case 1005:
        return 0.0;
    }
    return dTanH(x);
  }

double CNeuron::tanH(double x){
  //output range [-1.0..1.0]
   double result = MathTanh(x);
   if(!MathIsValidNumber(result)) {
     result = x < 0 ? -1.0 : 1.0;
   }   
   return result;
}

double CNeuron::dTanH(double x){
  double result = 1/MathPow(MathCosh(x),2);
   if(!MathIsValidNumber(result))
      Print("CNeuron::activationFunctionDerivative not a number for ", x);
   return result;
}

double CNeuron::identFunc(double x){
  return x;
}

double CNeuron::dIdentFunc(double x){
  return 1;
}

double CNeuron::ReLU(double x){
  return MathMax(0, x);
}

double CNeuron::dReLU(double x){
  return x < 0 ? 0 : 1;
}

double CNeuron::LeakyReLU(double x){
  return x < 0 ? 0.01 * x : x;
}

double CNeuron::dLeakyReLU(double x){
  return x < 0 ? 0.01 : 1;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CNeuron::feedForward(const CArrayObj *&prevLayer)
  {
   double sum=0.0;
   int total=prevLayer.Total();
   for(int n=0; n<total && !IsStopped(); n++)
     {
      CNeuron *temp=prevLayer.At(n);
      double val=temp.getOutputVal();
      if(val!=0)
        {
         CConnection *con = Connections.At(n);
         sum+=val * con.weight;
        }
     }

   outputVal=activationFunction(sum);
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CNeuron::sumWeightedDerivOfError(const CArrayObj *&nextLayer) const
  {
   double sum=0.0;
   int total=nextLayer.Total();
   for(int n=0; n<total; n++)
     {
      CNeuron *neuron = nextLayer.At(n);
      CConnection *con = neuron.Connections.At(myIndex);
      double weight=con.weight;
      if(weight!=0)
        {
         sum+=weight*neuron.gradient;
        }
     }

   return sum;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CNeuron::calcHiddenGradients(const CArrayObj *&nextLayer)
  {
   double dow = sumWeightedDerivOfError(nextLayer);//NormalizeDouble(sumWeightedDerivOfError(nextLayer),5);
   gradient=(dow!=0 ? dow*CNeuron::activationFunctionDerivative(outputVal) : 0);
   gradientSum += gradient;
   count++;
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CNeuron::calcOutputGradients(double targetVal)
  {
   double delta = targetVal-outputVal;//NormalizeDouble(targetVal-outputVal,5);
   gradient=(delta!=0 ? delta*CNeuron::activationFunctionDerivative(outputVal) : 0);
   gradientSum += gradient;
   count++;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CNeuron::updateInputWeights(CArrayObj *&prevLayer)
  {
   int total=Connections.Total();
   for(int n = 0; n < total && !IsStopped(); n++)
     {
      CNeuron *neuron = prevLayer.At(n);
      CConnection *con = Connections.At(n);

      //con.weight+=con.deltaWeight=(gradient!=0 ? eta*neuron.getOutputVal()*gradient : 0)+(con.deltaWeight!=0 ? alpha*con.deltaWeight : 0);
      con.weight+=con.deltaWeight=(gradientSum != 0 ? eta*neuron.getOutputVal()*gradientSum/count : 0)+(con.deltaWeight!=0 ? alpha*con.deltaWeight : 0);
     }
    gradientSum = 0;
    count = 0;  
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CNeuron::Save(int const file_handle){
  if (!FileWriteInteger(file_handle, activationType)) return false;
  return Connections.Save(file_handle);
}

bool CNeuron::Load(int const file_handle){
  activationType = FileReadInteger(file_handle);
  return Connections.Load(file_handle);
}
//+------------------------------------------------------------------+
//| class CNeuronId passes input forward from assigned index w/o altering it
//+------------------------------------------------------------------+
class CNeuronId   :  public CNeuron
  {
public:
                     CNeuronId(uint numInputs, uint index, uint indexOfInput);
   bool              updateInputWeights(CArrayObj *&prevLayer) { /* do nothing */ return true; };
   int               Type() { return CNEURON_IDENT; }
private:
   uint              inputIndex;
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
CNeuronId::CNeuronId(uint numInputs, uint index, uint indexOfInput)
  {
   eta = 0.1;
   alpha = 0.9;
   Connections = new CArrayCon();
   for(uint c = 0; c < numInputs; c++)
     {
      CConnection *con;
      if(c == indexOfInput)
         con = new CConnection(1.0);
      else
         con = new CConnection(0.0);
      Connections.Add(con);
     }
   inputIndex = indexOfInput;
   myIndex = index;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CNeuronBasis   :  public CNeuron
  {
public:
                     CNeuronBasis(uint numInputs, uint index);
   bool              updateInputWeights(CArrayObj *&prevLayer) { /* do nothing */ return true; }
   int               Type() { return CNEURON_BASIS; }
private:
   double            activationFunction(double x) { return 1.0; }
   double            activationFunctionDerivative(double x) {return 0.0; }
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
CNeuronBasis::CNeuronBasis(uint numInputs,uint index)
  {
   eta = 0.0001;
   alpha = 0.95;
   Connections = new CArrayCon();
   for(uint c = 0 ; c < numInputs; c++)
     {
      CConnection *con = new CConnection(0.0);
      Connections.Add(con);
     }
   myIndex = index;
  }
//+------------------------------------------------------------------+
//| class CLayer holds an array of Neurons                           |
//+------------------------------------------------------------------+
class CLayer: public CArrayObj
  {
private:
   uint              iInputs;
public:
                     CLayer(const uint inputs=0) { iInputs = inputs; };
   //---
   virtual bool      CreateElement(const uint index, const int activationType = 0, const int type = 1002);
   virtual int       Type(void) const { return(0x7779); }
   bool              Save(const int file_handle);
   bool              Load(const int file_handle);
  };

bool CLayer::CreateElement(const uint index, const int activationType = 0, const int type = 1002)
  {
//---
   if(m_data_max<(int)index+1)
     {
      if(ArrayResize(m_data,index+10)<=0)
        {
         Print("CLayer::CreateElement Error resizing array");
         return false;
        }
      m_data_max=ArraySize(m_data)-1;
     }
//---
   CNeuron *neuron;
   switch (type){
      case 1002:
        neuron = new CNeuron(iInputs,index, activationType);
        break;
      case 1005:
        neuron = new CNeuronBasis(iInputs, index);
        break;
      default:
        neuron = new CNeuron(iInputs,index, activationType);
   }
   if(!CheckPointer(neuron)!=POINTER_INVALID)
     {
      Print("CLayer::CreateElement Error creating neuron");
      return false;
     }
   neuron.setOutputVal((index%3)-1);
//---
   m_data[index]=neuron;
   m_data_total++;
//m_data_total=(int)MathMax(m_data_total,index);
//---
   return (true);
  }

bool CLayer::Save(const int file_handle){
  if (!FileWriteInteger(file_handle, Total())) return false;
  CNeuronBase *neuron;
  bool result = true;
  for (int i = 0; i < Total(); i++){
    neuron = At(i);
    result = result && neuron.Save(file_handle);
  }
  return result;
}

bool CLayer::Load(const int file_handle){
  int count = FileReadInteger(file_handle);
  for (int i = 0; i < count; i++){
    CNeuronBase *neuron = new CNeuron();
    neuron.Load(file_handle);
    Add(neuron);
  }
  return true;
}
//+------------------------------------------------------------------+
//| class CArrayLayer holds an array of neural layers                |
//+------------------------------------------------------------------+
class CArrayLayer  :    public CArrayObj
  {
public:
                     CArrayLayer(void) {};
                    ~CArrayLayer(void) {};
   //---
   virtual bool      CreateElement(const uint neurons, const uint inputs, const int activationType = 0, const bool hasBasis = false);
   virtual int       Type(void) const { return(0x7780); }
  };

bool CArrayLayer::CreateElement(const uint neurons, const uint inputs, const int activationType = 0, const bool hasBasis = false)
  {
   if(neurons<=0)
      return false;
//---
   if(m_data_max<=m_data_total)
     {
      if(ArrayResize(m_data,m_data_total+10)<=0)
         return false;
      m_data_max=ArraySize(m_data)-1;
     }
//---
   CLayer *layer=new CLayer(inputs);
   if(!CheckPointer(layer)!=POINTER_INVALID)
      return false;
   for(uint i=0; i<neurons; i++)
     {
      if (hasBasis && i == 0){
        if (!layer.CreateElement(i, activationType, CNEURON_BASIS))
          return false;
      }
      else if(!layer.CreateElement(i, activationType))
         return false;
     }

//---
   m_data[m_data_total]=layer;
   m_data_total++;
//---
   return (true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CNet
  {
public:
                     CNet(const CArrayInt *topology);
                     CNet(uint numInputs);
                     CNet(uint numInputs,const CArrayInt *topology, uint index,uint inputFrom,uint inputTo);
                     CNet() { }
                    ~CNet() {};
   
   void              setLearningRate(double rate);
   void              setMomentum(double m);
   void              feedForward(const CArrayDouble *inputVals);
   virtual bool      calcHiddenGradients(const CArrayObj *&nextLayer);
   virtual bool      updateInputWeights(CArrayObj *&prevLayer);
   void              backProp(const CArrayDouble *targetVals);
   void              getResults(CArrayDouble *&resultVals) const;
   void              batchTrain(const CArrayObj *inputValsArray, const CArrayObj *targetValsArray);
   double            getRecentAverageError() const { return recentAverageError; }
   uint              getOutputCount();
   bool              copyWeights(CNet *destination);
   bool              Save(const int file_handle);
   bool              Save(const string file_name, double error, double undefine, double forecast, datetime time, bool common=true);
   bool              Save(const string file_name);
   bool              Load(const int file_handle);
   bool              Load(const string file_name, double &error, double &undefine, double &forecast, datetime &time, bool common=true);
   bool              Load(const string file_name);
   virtual int       Type() const { return CNEURON_NET; }
   //---
   CArrayLayer       layers;
   static double     recentAverageSmoothingFactor;
private:
   double            recentAverageError;
  };

double CNet::recentAverageSmoothingFactor=100.0; // Number of training samples to average over

CNet::CNet(const CArrayInt *topology)
  {
   if(CheckPointer(topology)==POINTER_INVALID)
     {
      Print("CNet::CNet Invalid pointer: topology");
      return;
     }
//---
   int numLayers=topology.Total();
   for(int layerNum=0; layerNum<numLayers; layerNum++)
     {
      uint numInputs = (layerNum == 0 ? 0 : topology.At(layerNum - 1));
      int activationFunction = layerNum == numLayers - 1 ? LINEAR : TANH;
      if(!layers.CreateElement(topology.At(layerNum), numInputs, activationFunction, layerNum != 0 && layerNum != numLayers - 1 ? true : false))
        {
         Print("CNet::CNet Failed to create layer number", layerNum);
         return;
        }
     }
  }

void CNet::setLearningRate(double rate){
  CLayer *layer;
  for (int i = 0; i < layers.Total(); i++){
    layer = layers.At(i);
    CNeuron *neuron;
    for (int j = 0; j < layer.Total(); j++){
      neuron = layer.At(j);
      neuron.setLearningRate(rate);
    }
  }
}

void CNet::setMomentum(double m){
  CLayer *layer;
  for (int i = 0; i < layers.Total(); i++){
    layer = layers.At(i);
    CNeuron *neuron;
    for (int j = 0; j < layer.Total(); j++){
      neuron = layer.At(j);
      neuron.setMomentum(m);
    }
  }
}

void CNet::feedForward(const CArrayDouble *inputVals)
  {
//Print("feedForward called");
   if(CheckPointer(inputVals)==POINTER_INVALID)
     {
      Print("CNet::feedForward invalid pointer inputVals");
      return;
     }
//---
   CLayer *Layer=layers.At(0);
   if(CheckPointer(Layer)==POINTER_INVALID)
     {
      Print("CNet::feedForward invalid pointer Layer");
      return;
     }
   int total=inputVals.Total();
   if(total != Layer.Total())
     {
      Print("CNet::feedForward inputVals does not match input layer");
      Print("CNet::feedForward inputVals = ", total, "Layer total = ", Layer.Total());
      return;
     }
   for (int i = 0; i < inputVals.Total(); i++){
     if (inputVals.At(i) > 1.0 || inputVals.At(i) < -1.0){
       Print("CNet::feedForward input not normed");
     }
   }  
//---
   for(int i=0; i<total && !IsStopped(); i++)
     {
      CNeuron *neuron=Layer.At(i);
      neuron.setOutputVal(inputVals.At(i));
     }
//---
   total=layers.Total();
   for(int layerNum=1; layerNum<total && !IsStopped(); layerNum++)
     {
      CArrayObj *prevLayer = layers.At(layerNum - 1);
      CArrayObj *currLayer = layers.At(layerNum);
      int t=currLayer.Total();
      for(int n=0; n<t && !IsStopped(); n++)
        {
         CNeuron *neuron=currLayer.At(n);
         neuron.feedForward(prevLayer);
        }
     }
  }

bool CNet::calcHiddenGradients(const CArrayObj *&nextLayer)
  {
   bool result = true;
   CLayer *hiddenLayer = layers.At(layers.Total() - 1);
   for(int n = 0; n < hiddenLayer.Total() && !IsStopped(); n++)
     {
      CNeuron *neuron = hiddenLayer.At(n);
      result = result && neuron.calcHiddenGradients(nextLayer);
     }
   for(int layerNum=layers.Total()-2; layerNum>=0; layerNum--)
     {
      hiddenLayer=layers.At(layerNum);
      CArrayObj *nLayer=layers.At(layerNum+1);
      for(int n=0; n < hiddenLayer.Total() && !IsStopped(); ++n)
        {
         CNeuron *neuron=hiddenLayer.At(n);
         result = result && neuron.calcHiddenGradients(nLayer);
        }
     }
//---

   return result;
  }

bool CNet::updateInputWeights(CArrayObj *&prevLayer)
  {
   bool result = true;
   for(int layerNum=layers.Total()-1; layerNum>0; layerNum--)
     {
      CArrayObj *layer=layers.At(layerNum);
      CArrayObj *pLayer=layers.At(layerNum-1);
      for(int n=0; n < layer.Total() && !IsStopped(); n++)
        {
         CNeuron *neuron=layer.At(n);
         result = result && neuron.updateInputWeights(pLayer);
        }
     }
   CLayer *layer = layers.At(0);
   for(int n = 0; n < layer.Total() && !IsStopped(); n++)
     {
      CNeuron *neuron = layer.At(n);
      result = result && neuron.updateInputWeights(prevLayer);
     }
   return result;
  }

void CNet::backProp(const CArrayDouble *targetVals)
  {
   if(CheckPointer(targetVals)==POINTER_INVALID)
      return;
   CLayer *outputLayer=layers.At(layers.Total()-1);
   if(CheckPointer(outputLayer)==POINTER_INVALID)
      return;
//---
   double error=0.0;
   int total=outputLayer.Total();
   for(int n=0; n<total && !IsStopped(); n++)
     {
      CNeuron *neuron=outputLayer.At(n);
      double delta=targetVals[n]-neuron.getOutputVal();
      error+=delta*delta;
     }
   error/= total;
   error = sqrt(error);

   recentAverageError+=(error-recentAverageError)/recentAverageSmoothingFactor;
//---
   for(int n=0; n<total && !IsStopped(); n++)
     {
      CNeuron *neuron=outputLayer.At(n);
      neuron.calcOutputGradients(targetVals.At(n));
     }
//---
   for(int layerNum=layers.Total()-2; layerNum>0; layerNum--)
     {
      CArrayObj *hiddenLayer=layers.At(layerNum);
      CArrayObj *nextLayer=layers.At(layerNum+1);
      total=hiddenLayer.Total();
      for(int n=0; n<total && !IsStopped(); ++n)
        {
         CNeuron *neuron=hiddenLayer.At(n);
         neuron.calcHiddenGradients(nextLayer);
        }
     }
//---
   for(int layerNum=layers.Total()-1; layerNum>0; layerNum--)
     {
      CArrayObj *layer=layers.At(layerNum);
      CArrayObj *prevLayer=layers.At(layerNum-1);
      total=layer.Total();
      for(int n=0; n<total && !IsStopped(); n++)
        {
         CNeuron *neuron=layer.At(n);
         neuron.updateInputWeights(prevLayer);
        }
     }
  }

void CNet::getResults(CArrayDouble *&resultVals) const
  {
   if(CheckPointer(resultVals)==POINTER_INVALID)
     {
      Print("CNet::getResults invalid pointer resultVals");
      resultVals=new CArrayDouble();
     }
//---
   resultVals.Clear();
   CLayer *Layer=layers.At(layers.Total()-1);
   if(CheckPointer(Layer)==POINTER_INVALID)
     {
      Print("CNet::getResults invalid pointer Layer");
      return;
     }
   int total=Layer.Total();
   for(int n=0; n<total; n++)
     {
      CNeuron *neuron=Layer.At(n);
      resultVals.Add(neuron.getOutputVal());
      //Print("CNet: neuron output: " + DoubleToString(neuron.getOutputVal()));
     }
  }

void CNet::batchTrain(const CArrayObj *inputValsArray, const CArrayObj *targetValsArray){
  // Feed forward and calculate the hidden gradients for each sample in the batch
  for (int i = 0; i < inputValsArray.Total(); i++){
    feedForward(inputValsArray.At(i));
    CArrayDouble *targetVals = targetValsArray.At(i);
    if(CheckPointer(targetVals)==POINTER_INVALID)
     return;
    CLayer *outputLayer=layers.At(layers.Total()-1);
    if(CheckPointer(outputLayer)==POINTER_INVALID)
     return;

    // Calculate error
    double error=0.0;
    int total=outputLayer.Total();
    for(int n=0; n<total && !IsStopped(); n++)
    {
     CNeuron *neuron=outputLayer.At(n);
     double delta=targetVals[n]-neuron.getOutputVal();
     error+=delta*delta;
    }
    error/= total;
    error = sqrt(error);

    recentAverageError+=(error-recentAverageError)/recentAverageSmoothingFactor;

    // Calculate output gradients
    for(int n=0; n<total && !IsStopped(); n++)
     {
      CNeuron *neuron=outputLayer.At(n);
      neuron.calcOutputGradients(targetVals.At(n));
     }
    // Calculate hidden layer gradients
    for(int layerNum=layers.Total()-2; layerNum>0; layerNum--)
     {
      CArrayObj *hiddenLayer=layers.At(layerNum);
      CArrayObj *nextLayer=layers.At(layerNum+1);
      total=hiddenLayer.Total();
      for(int n=0; n<total && !IsStopped(); ++n)
        {
         CNeuron *neuron=hiddenLayer.At(n);
         neuron.calcHiddenGradients(nextLayer);
        }
     }
  }

  // Update neuron weights using the average gradient (calculated at the neuron level)
  for(int layerNum=layers.Total()-1; layerNum>0; layerNum--)
     {
      CArrayObj *layer=layers.At(layerNum);
      CArrayObj *prevLayer=layers.At(layerNum-1);
      int total=layer.Total();
      for(int n=0; n<total && !IsStopped(); n++)
        {
         CNeuron *neuron=layer.At(n);
         neuron.updateInputWeights(prevLayer);
        }
     }
}

bool CNet::copyWeights(CNet *destination){
  if (destination.layers.Total() != layers.Total()) return false;
  CLayer *layer, *dLayer;
  for (int i = 0; i < layers.Total(); i++){
    layer = layers.At(i);
    dLayer = destination.layers.At(i);
    CNeuronBase *neuron, *dNeuron;
    for (int j = 0; j < layer.Total(); j++){
      neuron = layer.At(j);
      dNeuron = dLayer.At(j);
      CArrayCon *conArr = neuron.Connections;
      CArrayCon *dConArr = dNeuron.Connections;
      dConArr.Clear();
      CConnection *con, *dCon;
      for (int k = 0; k < conArr.Total(); k++){
        con = conArr.At(k);
        dCon = new CConnection(con.weight, con.deltaWeight);
        dConArr.Add(dCon);
        //Print("CNet::copyWeights() " + DoubleToString(dCon.weight));
      }
      //Print("conArr total = " + DoubleToString(conArr.Total()) + "dConArr total = " + DoubleToString(dConArr.Total()));      
    }
  }
  return true;
}

bool CNet::Save(const int file_handle){
  if (!FileWriteInteger(file_handle, layers.Total())) return false;
  bool result = true;
  CLayer *layer;
  for (int i = 0; i < layers.Total(); i++){
    layer = layers.At(i);
    result = result && layer.Save(file_handle);
  }
  if (result)
    Print("CNet saving " + IntegerToString(layers.Total()) + " layers");
  else
    Print("Error saving CNet");  
  return result;
}

bool CNet::Save(const string file_name, double loop_err, double undefine_p, double forecast_er,datetime time, bool common=true)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) || MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_FORWARD) || MQLInfoInteger(MQL_OPTIMIZATION))
      return true;
   if(file_name==NULL)
      return false;
//---
   int handle=FileOpen(file_name,(common ? FILE_COMMON : 0)|FILE_BIN|FILE_WRITE);
   if(handle==INVALID_HANDLE)
      return false;
//---
   if(FileWriteDouble(handle,loop_err)<=0 || FileWriteDouble(handle,undefine_p)<=0 || FileWriteDouble(handle,forecast_er)<=0 || FileWriteLong(handle,(long)time)<=0)
     {
      FileClose(handle);
      return false;
     }
   bool result=layers.Save(handle);
   FileFlush(handle);
   FileClose(handle);
//---
   return result;
  }

bool CNet::Save(const string file_name){
  ResetLastError();
  int file_handle = FileOpen(file_name, FILE_WRITE | FILE_BIN);
  if (file_handle != INVALID_HANDLE)
  {
    Save(file_handle);
    FileClose(file_handle);
    Print("CNet successfully saved " + file_name);
    return true;
  }
  else
  {
    Print("CNet failed to save " + file_name + " error ", GetLastError());
    return false;
  }
}

bool CNet::Load(const int file_handle){
  int num;
  layers.Clear();
  num = FileReadInteger(file_handle);
  for (int i = 0; i < num; i++){
    CLayer *layer = new CLayer();
    layer.Load(file_handle);
    layers.Add(layer);
  }
  
  Print("CNet loaded " + IntegerToString(layers.Total()) + " layers");
  return true;
}

bool CNet::Load(const string file_name, double &loop_err, double &undefine_p, double &forecast_er, datetime &time, bool common=true)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) || MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_FORWARD) || MQLInfoInteger(MQL_OPTIMIZATION))
      return false;
//---
   if(file_name==NULL)
      return false;
//---
   int handle=FileOpen(file_name,(common ? FILE_COMMON : 0)|FILE_BIN|FILE_READ);
   if(handle==INVALID_HANDLE)
      return false;
//---
   loop_err=FileReadDouble(handle);
   undefine_p=FileReadDouble(handle);
   forecast_er=FileReadDouble(handle);
   time=(datetime)FileReadLong(handle);
//---
   layers.Clear();
   int i=0,num;
//--- check
//--- read and check start marker - 0xFFFFFFFFFFFFFFFF
   if(FileReadLong(handle)==-1)
     {
      //--- read and check array type
      if(FileReadInteger(handle,INT_VALUE)!=layers.Type())
         return(false);
     }
//--- read array length
   num=FileReadInteger(handle,INT_VALUE);
//--- read array
   if(num!=0)
     {
      for(i=0; i<num; i++)
        {
         //--- create new element
         CLayer *Layer=new CLayer();
         if(!Layer.Load(handle))
            break;
         if(!layers.Add(Layer))
            break;
        }
     }
   FileClose(handle);
//--- result
   return(layers.Total()==num);
  }

bool CNet::Load(const string file_name){
  ResetLastError();
  int file_handle = FileOpen(file_name, FILE_READ | FILE_BIN);
  if (file_handle != INVALID_HANDLE)
  {
     Load(file_handle);
  FileClose(file_handle);
  Print("CNet successfully opened " + file_name);
  return true;
  }
  else
  {
    Print("CNet failed to open " + file_name + " error ", GetLastError());
    return false;
  }
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class DQN {

public:
                      DQN() ;
                      DQN(int numInputs, int numActions, string fileName);
                      DQN(int numInputs, CArrayInt *actions, string fileName);
                     ~DQN(void);
  bool                Save(const int file_handle);                   
  bool                Save(const string fileName);
  bool                Load(const int file_handle);
  bool                Load(const string fileName);                   
  void                setDataSource(CData *source);
  int                 pickAction(CArrayDouble *input_1, bool _explore = true, int from = 0, int toInclusive = -1);
  int                 pickAction(CArrayDouble *input_1, CArrayInt *availActionIds, bool _explore = true);
  double              getActionValue(int index);
  int                 getActionIndex (int actionId);
  void                storeTransition(CArrayDouble *action, double reward, CArrayDouble *input_2);
  void                train(int iterations, int batchSize = 1);
  int                 getNumActions() { return numActions; };
  int                 getNumInputs() {return numInputs; };
  void                setLearningRate(double r);
  void                setMomentum(double m);
  void                setExplorDelta(int num);
  void                setExplorRate(double val);
  double              getExplorDelta();
  double              getExplorProb();
  void                setActionWeight(int action, int weight);
  double              getRecentAverageError() { return actionValueNet.getRecentAverageError(); };
  int                 getActionsTaken() { return actionsTaken; };
  void                setWeightCopyInterval(int num) { weightResetInterval = num; };
  void                setDefaultAction(int action) { defaultAction = action; };

private:
  CData               *trainingData;
  CNet                *actionValueNet;
  CNet                *targetActionValueNet;
  CArrayDouble        *output;
  CArrayInt           actionWeights;
  CArrayInt           actionIds;
  int                 numInputs;
  int                 numActions;
  double              explorationRate;
  double              explorationDelta;
  void                updateExplorRate();
  double              learningRate;
  double              discount;
  string              file_name;
  int                 weightResetInterval;
  int                 trainingIterations;
  int                 minRecordsToTrain;
  int                 actionsTaken;
  int                 defaultAction;
};

DQN::DQN(){
  minRecordsToTrain = 10;
  
  explorationRate = 1.0;
  explorationDelta = 1.0 / 30000;

  learningRate = 0.1;
  discount = 0.8;

  weightResetInterval = 100;
  trainingIterations = 0;

  defaultAction = 0;

  actionsTaken = 0;
}

DQN::DQN(int _numInputs, int _numActions, string fileName){
  minRecordsToTrain = 10;
  file_name = fileName;
  numInputs = _numInputs;
  numActions = _numActions;
  for (int i = 0; i < numActions; i++){
    actionIds.Add(i);
  }
  
  explorationRate = 1.0;
  explorationDelta = 1.0 / 30000;

  learningRate = 0.1;
  discount = 0.8;

  weightResetInterval = 100;
  trainingIterations = 0;

  defaultAction = 0;

  actionsTaken = 0;

  CArrayInt *topology = new CArrayInt();
  topology.Add(numInputs);
  int hiddenNeuronCount = 2 * numInputs / 3 + numActions;
  topology.Add(hiddenNeuronCount / 2);
  topology.Add(hiddenNeuronCount / 2);
  topology.Add(numActions);
  actionValueNet = new CNet(topology);
  targetActionValueNet = new CNet(topology);
  delete topology;
  
  actionValueNet.copyWeights(targetActionValueNet);

  for (int i = 0; i < numActions; i++){
    actionWeights.Add(1);
  }  
}

DQN::DQN(int _numInputs, CArrayInt *_actions, string fileName){
  minRecordsToTrain = 10;
  file_name = fileName;
  numInputs = _numInputs;
  numActions = _actions.Total();
  actionIds.AddArray(_actions);
  
  explorationRate = 1.0;
  explorationDelta = 0.0;

  learningRate = 0.1;
  discount = 0.8;

  weightResetInterval = 100;
  trainingIterations = 0;

  defaultAction = 0;

  actionsTaken = 0;

  CArrayInt *topology = new CArrayInt();
  topology.Add(numInputs);
  int hiddenNeuronCount = 2 * numInputs / 3 + numActions;
  topology.Add(hiddenNeuronCount / 2);
  topology.Add(hiddenNeuronCount / 2);
  topology.Add(numActions);
  actionValueNet = new CNet(topology);
  targetActionValueNet = new CNet(topology);
  delete topology;
  
  actionValueNet.copyWeights(targetActionValueNet);

  for (int i = 0; i < numActions; i++){
    actionWeights.Add(1);
  } 
}

DQN::~DQN(){
  /*if (CheckPointer(trainingData) != POINTER_INVALID){
    delete trainingData;
  }*/
  if (CheckPointer(actionValueNet) != POINTER_INVALID){
    delete actionValueNet;
  }
  if (CheckPointer(targetActionValueNet) != POINTER_INVALID){
    delete targetActionValueNet;
  }
  if (CheckPointer(output) != POINTER_INVALID){
    delete output;
  }
}

bool DQN::Save(const int file_handle){
  if (FileWriteInteger(file_handle, numInputs) <= 0) return false;
  if (FileWriteInteger(file_handle, numActions) <= 0) return false;
  if (FileWriteDouble(file_handle, explorationRate) <= 0) return false;
  if (FileWriteDouble(file_handle, explorationDelta) <= 0) return false;
  if (FileWriteDouble(file_handle, learningRate) <= 0) return false;
  if (FileWriteDouble(file_handle, discount) <= 0) return false;
  if (FileWriteInteger(file_handle, weightResetInterval) <= 0) return false;
  if (FileWriteInteger(file_handle, actionsTaken) <= 0) return false;
  if (!actionWeights.Save(file_handle)) return false;
  if (!actionIds.Save(file_handle)) return false;
  // Save neural net
  actionValueNet.Save(file_handle);
  targetActionValueNet.Save(file_handle);
  return true;
}

bool DQN::Save(const string fileName){
  ResetLastError();
  int file_handle = FileOpen(fileName, FILE_WRITE | FILE_BIN);
  if (file_handle != INVALID_HANDLE)
  {
    if (Save(file_handle))
    {
      file_name = fileName;
    }
    FileClose(file_handle);
    Print("DQN successfully saved " + file_name);
    return true;
  }
  else
  {
    Print("DQN failed to save " + fileName + " error ", GetLastError());
    return false;
  }
}

bool DQN::Load(const int file_handle){
  numInputs = FileReadInteger(file_handle);
  numActions = FileReadInteger(file_handle);
  explorationRate = FileReadDouble(file_handle);
  explorationDelta = FileReadDouble(file_handle);
  learningRate = FileReadDouble(file_handle);
  discount = FileReadDouble(file_handle);
  weightResetInterval = FileReadInteger(file_handle);
  actionsTaken = FileReadInteger(file_handle);
  actionWeights.Load(file_handle);
  actionIds.Load(file_handle);
  if (CheckPointer(actionValueNet) == POINTER_INVALID){
    actionValueNet = new CNet();
  }
  actionValueNet.Load(file_handle);
  if (CheckPointer(targetActionValueNet) == POINTER_INVALID){
    targetActionValueNet = new CNet();
  }  
  targetActionValueNet.Load(file_handle);
  return true;
}

bool DQN::Load(const string fileName){
  ResetLastError();
  int file_handle = FileOpen(fileName, FILE_READ | FILE_BIN);
  if (file_handle != INVALID_HANDLE)
  {
     if (Load(file_handle)) {
      file_name = fileName;
     }
  FileClose(file_handle);
  Print("DQN successfully opened " + file_name);
  return true;
  }
  else
  {
    Print("DQN failed to open " + fileName + " error ", GetLastError());
    return false;
  }
}

void DQN::setDataSource(CData *source){
  trainingData = source;
}

int DQN::pickAction(CArrayDouble *input_1, CArrayInt *availActionIds, bool _explore = true){
  CArrayInt availActions;
  for (int i = 0; i < availActionIds.Total(); i++){
    availActions.Add(getActionIndex(availActionIds.At(i)));
  }

  /*string avail_action_string = "Available action indices: ";
  for (int i = 0; i < availActions.Total(); i++){
    avail_action_string += IntegerToString(availActions.At(i)) + " ";
  }
  Print(avail_action_string);*/
  
  // Generate Q values
  actionValueNet.feedForward(input_1);
  if (CheckPointer(output) == POINTER_INVALID){
    output = new CArrayDouble();
  }
  output.Clear();
  actionValueNet.getResults(output);

  actionsTaken++;
  updateExplorRate();
  if (_explore && (rand() % 10000) / 10000.0 < getExplorProb()){
    // Pick an action to explore
    int totalWeight = 0;
    for (int i = 0; i < availActions.Total() && i < actionWeights.Total(); i++){
      totalWeight += actionWeights.At(availActions.At(i));
    }
    int randNum = rand() % totalWeight;
    int total = 0;
    for (int i = 0; i < availActions.Total() && i < actionWeights.Total(); i++){
      total += actionWeights.At(availActions.At(i));
      if (randNum < total) return actionIds.At(availActions.At(i));
    }
    return defaultAction;
  }
  else {
    // Pick an action based on policy by choosing action with highest predicted Q-value
    double max = output.At(availActions.At(0));
    int index = 0;
    //CArrayInt ties;
    for (int i = 1; i < availActions.Total() && i < output.Total(); i++){
      if (output.At(availActions.At(i)) > max){
        max = output.At(availActions.At(i));
        index = i;
      } 
    }
    // If there's a tie for the max, randomly pick between them
    CArrayInt ties;
    ties.Add(index);
    for (int i = 0; i < availActions.Total() && i < output.Total(); i++){
      if (i != index && output.At(availActions.At(i)) == max){
        ties.Add(i);
      }
    }
    if (ties.Total() > 1){
      if (ties.Total() == availActions.Total()){
        Print("Broke a tie between " + IntegerToString(ties.Total()) + " with default action");
        return defaultAction;
      }
      Print("Broke a tie between " + IntegerToString(ties.Total()) + " with random action");
      index = ties.At(rand() % ties.Total());
      
    }
    return actionIds.At(availActions.At(index));
  }
}

int DQN::pickAction(CArrayDouble *input_1, bool _explore = true, int from = 0, int toInclusive = -1){
  int to = toInclusive == -1 ? numActions : toInclusive + 1;
  // Generate Q values
  actionValueNet.feedForward(input_1);
  if (CheckPointer(output) == POINTER_INVALID){
    output = new CArrayDouble();
  }
  output.Clear();
  actionValueNet.getResults(output);

  // Debug
  /*string input_string = "Inputs = ";
  for (int i = 0; i < input_1.Total(); i++){
    input_string += DoubleToString(input_1.At(i)) + ", ";
  }
  Print(input_string);

  string output_string = "Outputs = ";
  for (int i = 0; i < output.Total(); i++){
    output_string += DoubleToString(output.At(i)) + ", ";
  }
  Print(output_string);*/
 
  // Pick the action to take
  actionsTaken++;
  if (_explore && (rand() % 100) / 100.0 < getExplorProb()){
    //updateExplorRate();
    // Pick an action to explore
    //return from + rand() % (to - from);
    int totalWeight = 0;
    for (int i = from; i < to && i < actionWeights.Total(); i++){
      totalWeight += actionWeights.At(i);
    }
    int randNum = rand() % totalWeight;
    int total = 0;
    for (int i = from; i < to && i < actionWeights.Total(); i++){
      total += actionWeights.At(i);
      if (randNum < total) return actionIds.At(i);
    }
    return defaultAction;
  } else {
    // Pick an action based on policy by choosing action with highest predicted Q-value
    double max = output.At(from);
    int index = from;
    //CArrayInt ties;
    for (int i = from + 1; i < to && i < output.Total(); i++){
      if (output.At(i) > max){
        max = output.At(i);
        index = i;
      } 
    }
    // If there's a tie for the max, randomly pick between them
    CArrayInt ties;
    ties.Add(index);
    for (int i = from; i < to && i < output.Total(); i++){
      if (i != index && output.At(i) == max){
        ties.Add(i);
      }
    }
    if (ties.Total() > 1){
      if (ties.Total() == to - from){
        Print("Broke a tie between " + IntegerToString(ties.Total()) + " with default action");
        return defaultAction;
      }
      Print("Broke a tie between " + IntegerToString(ties.Total()) + " with random action");
      index = ties.At(rand() % ties.Total());
      
    }

    return actionIds.At(index);
  }
}

void DQN::setActionWeight(int action, int weight){
  actionWeights.Update(action, MathMax(0, weight));
}

double DQN::getActionValue(int index){
  return output.At(index);
}

int DQN::getActionIndex(int actionId){
  for (int i = 0; i < actionIds.Total(); i++){
    if (actionIds.At(i) == actionId) return i;
  }
  return -1;
}

void DQN::train(int iterations, int miniBatchSize = 1)
{
  Print("Training...");
  for (int i = 0; i < iterations && trainingData.Total() > minRecordsToTrain && !IsStopped(); i++)
  {
    // Create minibatch arrays for input and target values
    CArrayObj *inputValsArray = new CArrayObj();
    CArrayObj *targetValsArray = new CArrayObj();

    // Fill minibatch arrays
    for (int j = 0; j < miniBatchSize; j++)
    {
      // Pick a random state
      CDataRecord *record = new CDataRecord();
      // ERE algorithm for choosing transitions to train from
      int historyLen = (int)MathMax(trainingData.Total() * MathPow(0.996, i * 1000 / iterations), miniBatchSize);
      int index = MathMax(0, trainingData.Total() - 1 - rand() % historyLen);
      trainingData.getNormalizedRecord(record, index);
      //trainingData.getNormalizedRecord(record, rand() % trainingData.Total());
      // Add input_1 to minibatch array
      CArrayDouble *input_1 = new CArrayDouble();
      input_1.AssignArray(record.input_1);
      inputValsArray.Add(input_1);
      // Prepare target value array
      CArrayDouble *target = new CArrayDouble();
      // if input_2 exists, initialize target values with what is predicted by target net
      if (CheckPointer(record.input_2) != POINTER_INVALID)
      {
        targetActionValueNet.feedForward(record.input_2);
        targetActionValueNet.getResults(target);

        // Add in the reward for the action to get final target values
        for (int k = 0; k < target.Total(); k++)
        {
          if (record.expectedOutput.At(k) > 0)
          {
            target.Update(k, record.isEpisodeEnd ? record.reward : discount * target.At(k) + record.reward);
          }
        }

        // Add target vals to minibatch array
        targetValsArray.Add(target);
      }
      else
      {
        Print("DQN::train Missing input_2");
      }
      delete record;
    }

    // Train on minibatch
    actionValueNet.batchTrain(inputValsArray, targetValsArray);

    // Keep count of training iterations
    trainingIterations++;
    // Copy weights from actionValueNet to targetActionValueNet periodically
    if (trainingIterations % weightResetInterval == 0)
    {
      trainingIterations = 0;
      actionValueNet.copyWeights(targetActionValueNet);
      //Save(file_name);
    }
    // Delete pointers
    delete inputValsArray;
    delete targetValsArray;
  }
}

/*void DQN::train(int iterations, int batchSize = 1){
  Print("Training...");
  for (int i = 0; i < iterations && trainingData.Total() > minRecordsToTrain && !IsStopped(); i++)
  {
    // Pick a random state to train from
    //CDataRecord *record = trainingData.At(rand() % trainingData.Total());
    CDataRecord *record = new CDataRecord();
    trainingData.getNormalizedRecord(record, rand() % trainingData.Total());
    // Feed forward initial state
    actionValueNet.feedForward(record.input_1);
    // Prepare target value array with action array to start
    CArrayDouble *target = new CArrayDouble();
    //target.AddArray(record.expectedOutput);
    // if input_2 exists, initialize target values with what is predicted by target net
    if (CheckPointer(record.input_2) != POINTER_INVALID)
    {
      targetActionValueNet.feedForward(record.input_2);
      targetActionValueNet.getResults(target);

      // Add in the reward for the action to get final target values
      for (int j = 0; j < target.Total(); j++){
        if (record.expectedOutput.At(j) > 0)
        {
          target.Update(j, record.isEpisodeEnd ? record.reward : discount * target.At(j) + record.reward);
        } 
      }
    
      // Perform back propagation
      actionValueNet.backProp(target);

      // Keep count of training iterations
      trainingIterations++;
      // Copy weights from actionValueNet to targetActionValueNet periodically
      if (trainingIterations % weightResetInterval == 0)
      {
        trainingIterations = 0;
        actionValueNet.copyWeights(targetActionValueNet);
        //Save(file_name);
      }
      // Delete pointers
      delete target;
      delete record;
    }
    else
    {
      Print("DQN::train Missing input_2");
    }
  }
}*/

void DQN::setLearningRate(double r){
  actionValueNet.setLearningRate(r);
  targetActionValueNet.setLearningRate(r);
}

void DQN::setMomentum(double m){
  actionValueNet.setMomentum(m);
  targetActionValueNet.setMomentum(m);
}

double DQN::getExplorProb(){
  return explorationRate;
}

void DQN::updateExplorRate(){
  // Decrease probability of off-policy exploration action
  explorationRate -= explorationDelta;
  explorationRate = MathMax(explorationRate, 0.0);
}

void DQN::setExplorDelta(int num){
  explorationDelta = num > 0 ? 1.0 / num : 0;
}

void DQN::setExplorRate(double val){
  explorationRate = MathMax(val, 0);
}

double DQN::getExplorDelta(){
  return 1.0 / explorationRate;
}
//+------------------------------------------------------------------+
