//+------------------------------------------------------------------+
//|                                                  DataManager.mqh |
//|                                     Copyright 2021, Nathan Adams |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, Nathan Adams"
#property link "https://www.mql5.com"
#property strict
//+------------------------------------------------------------------+
//| include                                                          |
//+------------------------------------------------------------------+
#include <Arrays\ArrayDouble.mqh>
#include <Arrays\ArrayObj.mqh>
#include <Arrays\ArrayString.mqh>
#include <Arrays\ArrayInt.mqh>
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
extern int historyLength = 5000;
const string MAX_REWARD = "MAX_REWARD";
class CDataRecord : public CObject

{
public:
  CDataRecord();
  CDataRecord(datetime _time, CArrayDouble *_input_1, CArrayDouble *_expectedOutput, double _reward, CArrayDouble *_input_2, int _ticket = 0);
  ~CDataRecord(void);
  bool Save(const int file_handle);
  bool Load(const int file_handle);
  CDataRecord *clone();
  CArrayDouble *input_1;
  CArrayDouble *expectedOutput;
  double reward;
  CArrayDouble *input_2;
  bool isEpisodeEnd;
  datetime time;
  int ticket;
};

CDataRecord::CDataRecord(){
  input_1 = new CArrayDouble();
  expectedOutput = new CArrayDouble();
  reward = 0;
  input_2 = new CArrayDouble();
  time = TimeCurrent();
  isEpisodeEnd = false;
}

CDataRecord::CDataRecord(datetime _time, CArrayDouble *_input_1, CArrayDouble *_expectedOutput, double _reward, CArrayDouble *_input_2, int _ticket = 0)
{
  time = _time;
  input_1 = _input_1;
  expectedOutput = _expectedOutput;
  reward = _reward;
  input_2 = _input_2;
  isEpisodeEnd = false;
  ticket = _ticket;
}

CDataRecord::~CDataRecord(){
  if (CheckPointer(input_1) != POINTER_INVALID) delete input_1;
  if (CheckPointer(expectedOutput) != POINTER_INVALID) delete expectedOutput;
  if (CheckPointer(input_2) != POINTER_INVALID) delete input_2;
}

bool CDataRecord::Save(const int file_handle)
{
  if (!input_1.Save(file_handle))
    return false;
  if (!expectedOutput.Save(file_handle))
    return false;
  if (FileWriteDouble(file_handle, reward) <= 0)
    return false;
  if (!input_2.Save(file_handle))
    return false;
  string time_string = TimeToString(time);
  int length = StringLen(time_string);
  if (FileWriteInteger(file_handle, length) <= 0)
    return false;
  if (FileWriteString(file_handle, TimeToString(time), length) <= 0)
    return false;
  if (FileWriteInteger(file_handle, isEpisodeEnd) <= 0) return false;  
  return true;
}

bool CDataRecord::Load(const int file_handle)
{
  if (CheckPointer(input_1) == POINTER_INVALID)
    input_1 = new CArrayDouble();
  input_1.Load(file_handle);
  if (CheckPointer(expectedOutput) == POINTER_INVALID)
    expectedOutput = new CArrayDouble();
  expectedOutput.Load(file_handle);
  reward = FileReadDouble(file_handle);
  if (CheckPointer(input_2) == POINTER_INVALID)
    input_2 = new CArrayDouble();
  input_2.Load(file_handle);
  int length = FileReadInteger(file_handle);
  time = StringToTime(FileReadString(file_handle, length));
  isEpisodeEnd = FileReadInteger(file_handle);
  return true;
}

CDataRecord *CDataRecord::clone(){
        CDataRecord *newRecord = new CDataRecord();
        newRecord.input_1.AddArray(input_1);
        newRecord.input_2.AddArray(input_2);
        newRecord.expectedOutput.AddArray(expectedOutput);
        newRecord.reward = reward;
        newRecord.isEpisodeEnd = isEpisodeEnd;
        return newRecord;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CData : public CArrayObj
{
public:
  CData(void);
  ~CData(void);
  void setNamedDataRange(int start, int end, string name);
  void CalculateMaxValues();
  void UpdateMaxValues(int newRecordCount = 0);
  void NormalizeData();
  void NormalizeInputData(CArrayDouble *inputData);
  void getNormalizedRecord(CDataRecord *toFill, int index);
  double getMaxValue(string namedRange);
  double getMaxReward();
  double getActualValue(double value, string namedRange);
  bool Save(const int file_handle);
  bool Save(const string file_name);
  bool Load(const int file_handle);
  bool Load(const string file_name);
  void AddTransition(CDataRecord *r);
  void AddEpisode(CArrayObj *episode);
  void RemoveOldestRecords(int num);

private:
  CArrayString *rangeNames;
  CArrayInt *rangeStarts;
  CArrayInt *rangeEnds;
  CArrayDouble *maxValues;
  double maxReward;
  string fileName;
  void NormalizeArray(CArrayDouble *arr);
};

CData::CData()
{
  rangeNames = new CArrayString();
  rangeStarts = new CArrayInt();
  rangeEnds = new CArrayInt();
  maxValues = new CArrayDouble();
}

CData::~CData(){
  if (CheckPointer(rangeNames) != POINTER_INVALID) delete rangeNames;
  if (CheckPointer(rangeStarts) != POINTER_INVALID) delete rangeStarts;
  if (CheckPointer(rangeEnds) != POINTER_INVALID) delete rangeEnds;
  if (CheckPointer(maxValues) != POINTER_INVALID) delete maxValues;
}

void CData::setNamedDataRange(int start, int end, string name)
{
  rangeNames.Add(name);
  rangeStarts.Add(start);
  rangeEnds.Add(end);
}

void CData::CalculateMaxValues()
{
  maxValues.Clear();
  // Calculate max value for each named range
  string maxes_string = "maxes = ";
  CDataRecord *record;
  double max;
  
  for (int i = 0; i < rangeNames.Total(); i++)
  {
    record = At(0);
    max = 0.0;//MathAbs(record.input_1.At(rangeStarts.At(i)));
    max = 0.0;//MathMax(max, MathAbs(record.input_2.At(rangeStarts.At(i))));
    for (int j = 0; j < Total(); j++)
    {
      record = At(j);
      for (int k = rangeStarts.At(i); k < rangeEnds.At(i); k++)
      {
        max = MathMax(max, MathAbs(record.input_1.At(k)));
        max = MathMax(max, MathAbs(record.input_2.At(k)));
        //Print(DoubleToString(record.input_1.At(k)));
      }
    }
    max = max == 0.0 ? 1.0 : max;
    maxValues.Add(max);
    maxes_string += DoubleToString(max) + " ";
  }
  //Print(maxes_string);
  // Calculate max reward
  /*record = At(0);
  if (CheckPointer(record) != POINTER_INVALID){
    max = MathAbs(record.reward);
    for (int i = 0; i < Total(); i++)
    {
      record = At(i);
      max = MathMax(max, MathAbs(record.reward));
    }
    maxReward = max;
  }*/
  maxReward = 1.0;
}

void CData::UpdateMaxValues(int newRecordCount = 0){
  CDataRecord *record;
  for (int i = 0; i < rangeNames.Total(); i++){
    for (int j = rangeStarts.At(i); j < rangeEnds.At(i); j++){
      for (int k = Total() - newRecordCount; k < Total(); k++){
        record = At(k);
        maxValues.Update(i, MathMax(maxValues.At(i), record.input_1.At(j)));
        maxValues.Update(i, MathMax(maxValues.At(i), record.input_2.At(j)));
      }
    }
  }
}

void CData::NormalizeData()
{
  CalculateMaxValues();
  CDataRecord *record;
  for (int i = 0; i < rangeNames.Total(); i++)
  {
    for (int j = 0; j < Total(); j++)
    {
      for (int k = rangeStarts.At(i); k < rangeEnds.At(i); k++)
      {
        record = At(j);
        record.input_1.Update(k, record.input_1.At(k) / maxValues.At(i));
        record.input_2.Update(k, record.input_2.At(k) / maxValues.At(i));
        //Print(rangeNames.At(i) + DoubleToString(record.input_1.At(k)));
      }
    }
  }
  for (int i = 0; i < Total(); i++){
    record = At(i);
    record.reward = record.reward / maxReward;
  }
  // Check values
  bool normalized1 = true, normalized2 = true, normalized3 = true;
  for (int i = 0; i < Total(); i++){
    record = At(i);
    for (int j = 0; j < record.input_1.Total(); j++){
      if (record.input_1.At(j) > 1.0 || record.input_1.At(j) < -1.0){
        normalized1 = false;
      }
    }
    for (int j = 0; j < record.input_2.Total(); j++){
      if (record.input_2.At(j) > 1.0 || record.input_2.At(j) < -1.0){
        normalized2 = false;
      }
    }
    if (record.reward > 1.0 || record.reward < -1.0){
      normalized3 = false;
    }
  }
  if (!normalized1) Print("Input_1 not normalized");
  if (!normalized2) Print("Input_2 not normalized");
  if (!normalized3) Print("Reward not normalized");
}

void CData::NormalizeInputData(CArrayDouble *inData){
  for (int i = 0; i < rangeNames.Total(); i++){
    for (int k = rangeStarts.At(i); k < rangeEnds.At(i); k++){
      double value = inData.At(k) / maxValues.At(i);
      value = MathMin(value, 1.0);
      value = MathMax(value, -1.0);
      inData.Update(k, value);
    }
  }
}

void CData::getNormalizedRecord(CDataRecord *toFill, int index){
  CDataRecord *record = At(index);
  
  if (CheckPointer(record) == POINTER_INVALID){
    Print("index = ", index);
  }
  // Fill input_1 with normed values from record
  if (CheckPointer(toFill.input_1) == POINTER_INVALID){
    toFill.input_1 = new CArrayDouble();
  }
  for (int i = 0; i < rangeNames.Total(); i++){
    for (int k = rangeStarts.At(i); k < rangeEnds.At(i); k++){
      double value = record.input_1.At(k) / maxValues.At(i);
      value = MathMin(value, 1.0);
      value = MathMax(value, -1.0);
      toFill.input_1.Add(value);
    }
  }
  // Fill input_2 with normed values from record
  if (CheckPointer(toFill.input_2) == POINTER_INVALID){
    toFill.input_2 = new CArrayDouble();
  }
  for (int i = 0; i < rangeNames.Total(); i++){
    for (int k = rangeStarts.At(i); k < rangeEnds.At(i); k++){
      double value = record.input_2.At(k) / maxValues.At(i);
      value = MathMin(value, 1.0);
      value = MathMax(value, -1.0);
      toFill.input_2.Add(value);
    }
  }  

  // Fill reward which does not get normed
  toFill.reward = record.reward;

  // Fill normed action/expected output array
  if (CheckPointer(toFill.expectedOutput) == POINTER_INVALID) toFill.expectedOutput = new CArrayDouble();
  for (int i = 0; i < record.expectedOutput.Total(); i++)
  {
    toFill.expectedOutput.Add(record.expectedOutput.At(i));
  }

  // Fill isEpisode end
  toFill.isEpisodeEnd = record.isEpisodeEnd;

}

double CData::getMaxValue(string namedRange)
{
  if (namedRange == MAX_REWARD)
  {
    return maxReward;
  }
  int index = rangeNames.Search(namedRange);
  if (index >= 0)
  {
    return maxValues.At(index);
  }
  else
  {
    return 0;
  }
}

double CData::getActualValue(double value, string namedRange)
{
  return value * getMaxValue(namedRange);
}

double CData::getMaxReward(){
  return maxReward;
}

void CData::NormalizeArray(CArrayDouble *arr)
{
  double max = MathAbs(arr.At(0));
  double min = MathAbs(arr.At(0));
  for (int j = 0; j < arr.Total(); j++)
  {
    max = MathMax(max, MathAbs(arr.At(j)));
    min = MathMin(min, MathAbs(arr.At(j)));
  }
  for (int j = 0; j < arr.Total(); j++)
    //arr.Update(j, (arr.At(j) - min) / (max - min));
    arr.Update(j, arr.At(j) / max);
}

bool CData::Save(const int file_handle)
{
  //Print("Saving rangeNames total = " + IntegerToString(rangeNames.Total()));
  if (!rangeNames.Save(file_handle))
    return false;
  if (!rangeStarts.Save(file_handle))
    return false;
  if (!rangeEnds.Save(file_handle))
    return false;
  if (!maxValues.Save(file_handle))
    return false;
  if (FileWriteInteger(file_handle, Total()) <= 0)
    return false;
  for (int i = 0; i < Total(); i++)
  {
    CDataRecord *r = At(i);
    r.Save(file_handle);
  }
  return true;
}

bool CData::Save(const string file_name)
{
  ResetLastError();
  int file_handle = FileOpen(file_name, FILE_WRITE | FILE_BIN);
  if (file_handle != INVALID_HANDLE)
  {
    if (Save(file_handle))
    {
      fileName = file_name;
    }
    FileFlush(file_handle);
    FileClose(file_handle);
    Print("CData successfully saved " + file_name);
    return true;
  }
  else
  {
    Print("CData failed to save " + file_name + " error ", GetLastError());
    return false;
  }
}

bool CData::Load(const int file_handle)
{
  if (CheckPointer(rangeNames) == POINTER_INVALID)
    rangeNames = new CArrayString();
  rangeNames.Load(file_handle);
  if (CheckPointer(rangeStarts) == POINTER_INVALID)
    rangeStarts = new CArrayInt();
  rangeStarts.Load(file_handle);
  if (CheckPointer(rangeEnds) == POINTER_INVALID)
    rangeEnds = new CArrayInt();
  rangeEnds.Load(file_handle);
  if (CheckPointer(maxValues) == POINTER_INVALID)
    maxValues = new CArrayDouble();
  maxValues.Load(file_handle);
  Clear();
  int total = FileReadInteger(file_handle);
  for (int i = 0; i < total; i++)
  {
    CDataRecord *r = new CDataRecord();
    r.Load(file_handle);
    Add(r);
  }
  return true;
}

bool CData::Load(const string file_name)
{
  ResetLastError();
  int file_handle = FileOpen(file_name, FILE_READ | FILE_BIN);
  if (file_handle != INVALID_HANDLE)
  {
     if (Load(file_handle)) {
      fileName = file_name;
     }
    FileClose(file_handle);
    Print("CData successfully opened " + file_name);
    return true;
  }
  else
  {
    Print("CData failed to open " + file_name + " error ", GetLastError());
    return false;
  }
}

void CData::AddEpisode(CArrayObj *episode)
{
      for (int i = 0; i < episode.Total(); i++){
        CDataRecord *r = episode.At(i);
        CDataRecord *newRecord = new CDataRecord();
        newRecord.input_1.AddArray(r.input_1);
        newRecord.input_2.AddArray(r.input_2);
        newRecord.expectedOutput.AddArray(r.expectedOutput);
        newRecord.reward = r.reward;
        newRecord.isEpisodeEnd = r.isEpisodeEnd;
        Add(newRecord);
      }
      if (Total() > historyLength){
        DeleteRange(0, episode.Total());
      }
      // Update max values
      if (Total() == episode.Total()) CalculateMaxValues();
      else UpdateMaxValues(episode.Total());
}

void CData::AddTransition(CDataRecord *r){
  //CDataRecord *newRecord = new CDataRecord();
  //newRecord.input_1.AddArray(r.input_1);
  //newRecord.input_2.AddArray(r.input_2);
  //newRecord.expectedOutput.AddArray(r.expectedOutput);
  //newRecord.reward = r.reward;
  //newRecord.isEpisodeEnd = r.isEpisodeEnd;
  //newRecord.ticket = r.ticket;
  Add(r);
  if (Total() > historyLength){
    DeleteRange(0, 1);
  }
  // Update max values
  if (Total() == 1) CalculateMaxValues();
  else UpdateMaxValues(1);
}

void CData::RemoveOldestRecords(int num){
  DeleteRange(0, num);
  double val = maxReward;
  NormalizeData();
  maxReward = val;
}
//+------------------------------------------------------------------+
