//+------------------------------------------------------------------+
//|                                                  TradeAction.mq4 |
//|                           TradeActions demo table (open orders)  |
//+------------------------------------------------------------------+
#property strict

// Visual inputs
input color InpPanelBackgroundColor = C'20,20,20';
input color InpPanelBorderColor     = C'130,130,130';
input color InpHeaderBackgroundColor= C'35,35,35';
input color InpGridColor            = C'85,85,85';
input color InpTextColor            = clrWhite;
input color InpTitleColor           = clrGold;
input color InpEmptyTextColor       = clrSilver;

// Table layout
string TA_PREFIX         = "TA_";
int    TA_MAX_ROWS       = 10;
int    TA_RIGHT_MARGIN   = 14;
int    TA_TOP_MARGIN     = 14;
int    TA_PADDING_X      = 8;
int    TA_PADDING_Y      = 8;
int    TA_TITLE_HEIGHT   = 22;
int    TA_HEADER_HEIGHT  = 20;
int    TA_ROW_HEIGHT     = 19;
int    TA_FONT_SIZE      = 9;
string TA_FONT_NAME      = "Tahoma";

// Column widths (pixels)
int COL_COUNT            = 5;
int COL_W_OPEN_CLOSE     = 100;
int COL_W_DIRECTION      = 110;
int COL_W_EXEC_PRICE     = 115;
int COL_W_EXPOSURE       = 90;
int COL_W_PROFIT         = 70;

void   DrawTable();
double GetExposure(double currentExposure = 0.0, int orderType = -1, double lots = 0.0);
void   ClearTable();
void   CreateRectangle(string name, int x, int y, int width, int height, color bgColor, color borderColor, int borderWidth = 1);
void   CreateTableLabel(string name, string text, int x, int y, color textColor, int fontSize, ENUM_ANCHOR_POINT anchor);
int    GetColumnWidth(int columnIndex);
string GetColumnTitle(int columnIndex);
int    GetContentWidth();
int    GetColumnStartX(int panelLeftX, int columnIndex);
string GetCellValue(int columnIndex, string openOrClose, string direction, string execPrice, string exposure, string profit);
int    FillSampleRows(string &rowOpenOrClose[], string &rowDirection[], string &rowExecutionPrice[], string &rowExposure[], string &rowProfit[]);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   DrawTable();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ClearTable();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   DrawTable();
  }

//+------------------------------------------------------------------+
//| Draw TradeActions table                                          |
//+------------------------------------------------------------------+
void DrawTable()
  {
   ClearTable();

   // Collect current open rows for this symbol
   string rowOpenOrClose[10];
   string rowDirection[10];
   string rowExecutionPrice[10];
   string rowExposure[10];
   string rowProfit[10];

   double runningExposure = 0.0;
   int displayedRows = 0;

   for(int i = 0; i < OrdersTotal() && displayedRows < TA_MAX_ROWS; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() != Symbol())
         continue;

      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL)
         continue;

      runningExposure = GetExposure(runningExposure, type, OrderLots());

      string direction = (type == OP_BUY) ? "buy" : "sell";
      rowOpenOrClose[displayedRows] = "open";
      rowDirection[displayedRows] = direction;
      rowExecutionPrice[displayedRows] = DoubleToString(OrderOpenPrice(), Digits);
      rowExposure[displayedRows] = DoubleToString(runningExposure, 2);
      rowProfit[displayedRows] = "";

      displayedRows++;
     }

      bool noOrders = false;
   if(displayedRows == 0)
     {
      noOrders = true;
     }

      displayedRows = 1;

   int contentWidth = GetContentWidth();
   int panelWidth = contentWidth + (TA_PADDING_X * 2);
   int panelHeight = (TA_PADDING_Y * 2) + TA_TITLE_HEIGHT + TA_HEADER_HEIGHT + (displayedRows * TA_ROW_HEIGHT);

   int chartWidth = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   if(chartWidth <= 0)
      chartWidth = 800;

   int panelLeft = chartWidth - TA_RIGHT_MARGIN - panelWidth;
   if(panelLeft < 0)
      panelLeft = 0;
   int panelTop = TA_TOP_MARGIN;

   int titleY = panelTop + TA_PADDING_Y;
   int headerY = titleY + TA_TITLE_HEIGHT;
   int bodyY = headerY + TA_HEADER_HEIGHT;

   // Panel + header area
   CreateRectangle("TA_Background", panelLeft, panelTop, panelWidth, panelHeight, InpPanelBackgroundColor, InpPanelBorderColor, 1);
   CreateRectangle("TA_HeaderBg", panelLeft + TA_PADDING_X, headerY, contentWidth, TA_HEADER_HEIGHT, InpHeaderBackgroundColor, InpGridColor, 1);

   // Grid lines
   int gridTop = headerY;
   int gridHeight = TA_HEADER_HEIGHT + (displayedRows * TA_ROW_HEIGHT);
   int splitX = panelLeft + TA_PADDING_X;

   for(int c = 0; c < COL_COUNT - 1; c++)
     {
      splitX += GetColumnWidth(c);
      CreateRectangle("TA_VLine_" + IntegerToString(c + 1), splitX, gridTop, 1, gridHeight, InpGridColor, InpGridColor, 1);
     }

   CreateRectangle("TA_HLine_Header", panelLeft + TA_PADDING_X, bodyY, contentWidth, 1, InpGridColor, InpGridColor, 1);

   for(int r = 1; r < displayedRows; r++)
     {
      int yLine = bodyY + (r * TA_ROW_HEIGHT);
      CreateRectangle("TA_HLine_Row_" + IntegerToString(r), panelLeft + TA_PADDING_X, yLine, contentWidth, 1, InpGridColor, InpGridColor, 1);
     }

   // Title
   CreateTableLabel("TA_Title", "TradeActions", panelLeft + TA_PADDING_X + 2, titleY + 2, InpTitleColor, TA_FONT_SIZE + 1, ANCHOR_LEFT_UPPER);

   // Header text
   for(int column = 0; column < COL_COUNT; column++)
     {
      int colStart = GetColumnStartX(panelLeft, column);
      CreateTableLabel("TA_Head_" + IntegerToString(column + 1), GetColumnTitle(column), colStart + 4, headerY + 3, InpTextColor, TA_FONT_SIZE, ANCHOR_LEFT_UPPER);
     }

   // Body rows
   if(noOrders)
     {
      CreateTableLabel("TA_Row_Empty", "No open BUY/SELL orders for this symbol", panelLeft + TA_PADDING_X + 4, bodyY + 3, InpEmptyTextColor, TA_FONT_SIZE, ANCHOR_LEFT_UPPER);
      return;
     }

   for(int row = 0; row < displayedRows; row++)
     {
      int rowY = bodyY + (row * TA_ROW_HEIGHT);

      for(int col = 0; col < COL_COUNT; col++)
        {
         string text = GetCellValue(col, rowOpenOrClose[row], rowDirection[row], rowExecutionPrice[row], rowExposure[row], rowProfit[row]);
         int colStart = GetColumnStartX(panelLeft, col);
         int colWidth = GetColumnWidth(col);

         bool rightAlign = (col == 2 || col == 3 || col == 4);
         if(rightAlign)
            CreateTableLabel("TA_Cell_" + IntegerToString(row + 1) + "_" + IntegerToString(col + 1), text, colStart + colWidth - 4, rowY + 3, InpTextColor, TA_FONT_SIZE, ANCHOR_RIGHT_UPPER);
         else
            CreateTableLabel("TA_Cell_" + IntegerToString(row + 1) + "_" + IntegerToString(col + 1), text, colStart + 4, rowY + 3, InpTextColor, TA_FONT_SIZE, ANCHOR_LEFT_UPPER);
        }
     }
  }

//+------------------------------------------------------------------+
//| Exposure helper                                                  |
//| - With args: update running exposure                             |
//| - Without args: calculate full net exposure for current symbol   |
//+------------------------------------------------------------------+
double GetExposure(double currentExposure, int orderType, double lots)
  {
   if(orderType == OP_BUY)
      return(currentExposure + lots);

   if(orderType == OP_SELL)
      return(currentExposure - lots);

   double totalExposure = 0.0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() != Symbol())
         continue;

      int type = OrderType();
      if(type == OP_BUY)
         totalExposure += OrderLots();
      else if(type == OP_SELL)
         totalExposure -= OrderLots();
     }

  return(totalExposure);
  }



//+------------------------------------------------------------------+
//| Remove all table objects                                         |
//+------------------------------------------------------------------+
void ClearTable()
  {
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
     {
      string name = ObjectName(i);
      if(StringFind(name, TA_PREFIX, 0) == 0)
         ObjectDelete(0, name);
     }
  }

//+------------------------------------------------------------------+
//| Create filled rectangle label                                    |
//+------------------------------------------------------------------+
void CreateRectangle(string name, int x, int y, int width, int height, color bgColor, color borderColor, int borderWidth)
  {
   if(width <= 0 || height <= 0)
      return;

   if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
      return;

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, borderColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, borderWidth);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
//| Create one label                                                 |
//+------------------------------------------------------------------+
void CreateTableLabel(string name, string text, int x, int y, color textColor, int fontSize, ENUM_ANCHOR_POINT anchor)
  {
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
      return;

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_FONT, TA_FONT_NAME);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

//+------------------------------------------------------------------+
//| Column metadata                                                   |
//+------------------------------------------------------------------+
int GetColumnWidth(int columnIndex)
  {
   switch(columnIndex)
     {
      case 0: return(COL_W_OPEN_CLOSE);
      case 1: return(COL_W_DIRECTION);
      case 2: return(COL_W_EXEC_PRICE);
      case 3: return(COL_W_EXPOSURE);
      case 4: return(COL_W_PROFIT);
     }
   return(80);
  }

//+------------------------------------------------------------------+
//| Column titles                                                    |
//+------------------------------------------------------------------+
string GetColumnTitle(int columnIndex)
  {
   switch(columnIndex)
     {
      case 0: return("OpenOrClose");
      case 1: return("TradeDirection");
      case 2: return("ExecutionPrice");
      case 3: return("Exposure");
      case 4: return("Profit");
     }
   return("");
  }

//+------------------------------------------------------------------+
//| Total content width                                               |
//+------------------------------------------------------------------+
int GetContentWidth()
  {
   int width = 0;
   for(int i = 0; i < COL_COUNT; i++)
      width += GetColumnWidth(i);

   return(width);
  }

//+------------------------------------------------------------------+
//| Pixel X start for one column                                     |
//+------------------------------------------------------------------+
int GetColumnStartX(int panelLeftX, int columnIndex)
  {
   int x = panelLeftX + TA_PADDING_X;
   for(int i = 0; i < columnIndex; i++)
      x += GetColumnWidth(i);

   return(x);
  }

//+------------------------------------------------------------------+
//| Resolve value by column index                                    |
//+------------------------------------------------------------------+
string GetCellValue(int columnIndex, string openOrClose, string direction, string execPrice, string exposure, string profit)
  {
   switch(columnIndex)
     {
      case 0: return(openOrClose);
      case 1: return(direction);
      case 2: return(execPrice);
      case 3: return(exposure);
      case 4: return(profit);
     }
   return("");
  }
//+------------------------------------------------------------------+
