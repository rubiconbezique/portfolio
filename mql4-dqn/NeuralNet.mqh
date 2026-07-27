//+------------------------------------------------------------------+
//|                                                    NeuralNet.mqh |
//|                                     Copyright 2019, Nathan Adams |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2019, Nathan Adams"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
class NeuralNet
  {
private:
   int         inputSize;
	int         outputSize;

	int         layer1Size, layer2Size;
	
	bool        l1Basis, l2Basis;

	double      L1Wghts[50][50];
	double      L2Wghts[50][50];
	double      outputWghts[50][50];
   double      output[];
   double      maxes[];
   
   double      sigmoid(double value);
public:
               NeuralNet(string filePath);
   void        process(double& inputValues[]);
   int         getOutputCount();
   double      getOutput(int index);
               ~NeuralNet();
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
NeuralNet::NeuralNet(string filePath)
  {
      int fileHandle = FileOpen(filePath, FILE_READ);
      if (fileHandle < 0){
         Alert("Failed to open file " + filePath + " error = " + IntegerToString(GetLastError()));
      } else {
         Alert("Success opening file " + filePath);
         string line;
         ushort sep = StringGetCharacter(",", 0);
         FileSeek(fileHandle, 0, SEEK_SET);
         while (!FileIsEnding(fileHandle)){
            line = FileReadString(fileHandle, 0); // Skip version number
            line = FileReadString(fileHandle, 0); // Skip learning rate and momentum
            
            line = FileReadString(fileHandle, 0); // Read input/output sizes
            string values[];
            StringSplit(line, sep, values);
            inputSize = StringToInteger(values[0]);
            outputSize = StringToInteger(values[1]);
            
            line = FileReadString(fileHandle, 0); // Read basis booleans
            StringSplit(line, sep, values);
            l1Basis = values[0] == "true";
            l1Basis = values[1] == "true";
            
            line = FileReadString(fileHandle, 0); // Read L1 weights size
            StringSplit(line, sep, values);
            layer1Size = StringToInteger(values[0]);
            
            for (int i = 0; i < layer1Size; i++){ // Read inpu -> L1 Weights
               line = FileReadString(fileHandle, 0);
               StringSplit(line, sep, values);
               for (int j = 0; j < inputSize; j++){
                  L1Wghts[i][j] = StringToDouble(values[j]);
               }
            }
            
            line = FileReadString(fileHandle, 0); // Read L2 weights size
            StringSplit(line, sep, values);
            layer2Size = StringToInteger(values[0]); 
            
            for (int i = 0; i < layer2Size; i++){ // Read L1 -> L2 weights
               line = FileReadString(fileHandle, 0);
               StringSplit(line, sep, values);
               for (int j = 0; j < layer1Size; j++){
                  L2Wghts[i][j] = StringToDouble(values[j]);
               }
            }
            
            line = FileReadString(fileHandle, 0); // Read output weights size (ignore, already known)
            
            for (int i = 0; i < outputSize; i++){ // Read output weights
               line = FileReadString(fileHandle, 0);
               StringSplit(line, sep, values);
               for (int j = 0; j < layer2Size; j++){
                  outputWghts[i][j] = StringToDouble(values[j]);
               }
            }
            
            line = FileReadString(fileHandle, 0);
            ArrayResize(maxes, inputSize + outputSize);
            StringSplit(line, sep, values);
            for (int i = 0; i < inputSize + outputSize; i++){
               maxes[i] = StringToDouble(values[i]);
            }
         }
         FileClose(fileHandle);
      }
  }
  
void NeuralNet::process(double &inputValues[]){
	double L1ActVals[];
	double L2ActVals[];
	double normValues[];
	ArrayResize(L1ActVals, layer1Size);
	ArrayResize(L2ActVals, layer2Size);
	ArrayResize(normValues, inputSize);
	ArrayResize(output, outputSize);
	
	for (int i = 0; i < inputSize; i++){
	   normValues[i] = inputValues[i] / maxes[i];
	}
	
	for (int r = 0; r < layer1Size; r++){ // r = 1 because L1,0 is a basis neuron
			if (l1Basis && r == 0) {
				L1ActVals[0] = 1.0; // L1,0 is a basis neuron so always = 1.0
			} else {
				double dotProduct = 0;
				for (int i = 0; i < inputSize; i++){
					dotProduct += normValues[i] * L1Wghts[r][i];
				}
				L1ActVals[r] = sigmoid(dotProduct);
			}
		}
	
		// Layer 1 to layer 2
		for (int r = 0; r < layer2Size; r++){ // r = 1 because L2,0 is a basis neuron 
			if (l2Basis && r == 0) {
				L2ActVals[0] = 1.0; // L2,0 is a basis neuron so always = 1.0
			} else {
				double dotProduct = 0;
				for (int i = 0; i < layer1Size; i++){
					dotProduct += L1ActVals[i] * L2Wghts[r][i];
				}
				L2ActVals[r] = sigmoid(dotProduct);
			}
		}

		// Layer 2 to outputSize
		for (int r = 0; r < outputSize; r++){
			double dotProduct = 0;
			for (int i = 0; i < layer2Size; i++){
				dotProduct += L2ActVals[i] * outputWghts[r][i];
			}
			output[r] = sigmoid(dotProduct);
		}
}

double NeuralNet::getOutput(int index){
   return output[index] * maxes[inputSize + index];
}

double NeuralNet::sigmoid(double value){
   return 1.0 / (1.0 + MathExp(-value));
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
NeuralNet::~NeuralNet()
  {
  }
//+------------------------------------------------------------------+
