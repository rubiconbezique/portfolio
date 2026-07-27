//+------------------------------------------------------------------+
//|                                                      UITools.mqh |
//|                                     Copyright 2021, Nathan Adams |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, Nathan Adams"
#property link      "https://www.mql5.com"
#property strict
//+------------------------------------------------------------------+
//| include                                                          |
//+------------------------------------------------------------------+
#include <Object.mqh>
#include <Button.mqh>
#include <Label.mqh>
#include <TrendLine.mqh>
#include <ArrowDown.mqh>
#include <ArrowUp.mqh>
#include <HorizLine.mqh>
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CButton : public CObject
  {
public:
                     CButton(const string _name, const int _x, const int _y, const int _width, const int _height, const string _text);
   bool                 isPressed();
   void                 Delete();

private:
   string               name;
   int                  x, y;
   int                  width, height;
   string               text;
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
CButton::CButton(const string _name,const int _x,const int _y,const int _width,const int _height,const string _text)
  {
   name = _name;
   x = _x;
   y = _y;
   width = _width;
   height = _height;
   text = _text;
   ButtonCreate(0, name, 0, x, y, width, height, CORNER_LEFT_UPPER, text);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CButton::isPressed(void)
  {
   return ButtonPressed(0, name);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CButton::Delete(void)
  {
   ButtonDelete(0, name);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CLabel : public CObject
  {
public:
                     CLabel(const string _name, const int _x, const int _y, const string _text, const int _font_size=10);
   void                 SetText(const string _text);
   void                 SetColor(const color _color);
   void                 Delete();

private:
   string               name;
   int                  x, y;
   int                  font_size;
   string               text;
   color                text_color;
  };

CLabel::CLabel(const string _name,const int _x,const int _y,const string _text,const int _font_size=10)
  {
   name = _name;
   x = _x;
   y = _y;
   font_size = _font_size;
   text = _text;
   text_color = C'0,0,0';
   LabelCreate(0, name, 0, x, y, CORNER_LEFT_UPPER, text, "Arial", font_size);
  }

void CLabel::SetText(const string _text)
{
   text = _text;
   LabelTextChange(0, name, text);
}

void CLabel::SetColor(const color _color)
{
   text_color = _color;
   LabelColorChange(0, name, text_color);
}

void CLabel::Delete(){
  LabelDelete(0, name);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CTrendLine : public CObject {
  public:
    CTrendLine(string name, datetime time1, double price1, datetime time2, double price2, color clr);
    ~CTrendLine();

  private:
    string name;
};

CTrendLine::CTrendLine(string _name, datetime time1, double price1, datetime time2, double price2, color clr) {
  name = _name;
  TrendCreate(0, name, 0, time1, price1, time2, price2, clr, STYLE_SOLID, 1, false, true, true);
}

CTrendLine::~CTrendLine(){
  TrendDelete(0, name);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CArrowDown : public CObject {
  public:
    CArrowDown(string name, datetime time, double price, color clr);
    ~CArrowDown();

  private:
    string name;
    datetime time;
    double price;
    color clr;
};

CArrowDown::CArrowDown(string _name, datetime _time, double _price, color _clr) {
  name = _name;
  time = _time;
  price = _price;
  clr = _clr;
  ArrowDownCreate(0, name, 0, time, price, ANCHOR_BOTTOM, clr, STYLE_SOLID);
}

CArrowDown::~CArrowDown(){
  ArrowDownDelete(0, name);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CArrowUp : public CObject {
  public:
    CArrowUp(string name, datetime time, double price, color clr);
    ~CArrowUp();

  private:
    string name;
    datetime time;
    double price;
    color clr;
};

CArrowUp::CArrowUp(string _name, datetime _time, double _price, color _clr) {
  name = _name;
  time = _time;
  price = _price;
  clr = _clr;
  ArrowUpCreate(0, name, 0, time, price, ANCHOR_TOP, clr, STYLE_SOLID);
}

CArrowUp::~CArrowUp(){
  ArrowUpDelete(0, name);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CHLine : public CObject {
  public:
    CHLine(string name, double price, color clr);
    ~CHLine();

  private:
    string name;
    double price;
    color clr;
};

CHLine::CHLine(string _name, double _price, color _clr) {
  name = _name;
  price = _price;
  clr = _clr;
  HLineCreate(0, name, 0, price, clr);
}

CHLine::~CHLine(){
  HLineDelete(0, name);
}

//+------------------------------------------------------------------+
