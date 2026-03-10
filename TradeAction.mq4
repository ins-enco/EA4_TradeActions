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
int COL_COUNT                        = 10;
int COL_W_OPEN_CLOSE                 = 95;
int COL_W_DIRECTION                  = 95;
int COL_W_EXEC_PRICE                 = 95;
int COL_W_EXPOSURE                   = 80;
int COL_W_TICKET                     = 90;
int COL_W_SYMBOL_NAME                = 95;
int COL_W_TICKET_DIRECTION           = 110;
int COL_W_MILLISECONDS_SINCE_LAST    = 160;
int COL_W_PRICE_DIFF_FROM_PREVIOUS   = 170;
int COL_W_PROFIT_SINCE_START         = 130;
int TA_ACTION_LOG_RETENTION          = 200;

string TA_ACTION_OPEN  = "open";
string TA_ACTION_CLOSE = "close";

struct TradeActionRow
  {
   int      ticket;
   string   openOrClose;
   string   symbolName;
   string   tradeDirection;
   double   executionPrice;
   double   lots;
   double   exposure;
   double   profit;
   string   ticketDirection;
   long     millisecondsSinceLastAction;
   double   priceDifferenceFromPrevious;
   double   profitSinceStart;
   datetime actionTime;
   long     actionTimeMs;
   int      ticketType;
  };

struct OpenTicketSnapshot
  {
   int      ticket;
   int      ticketType;
   double   lots;
   string   symbolName;
   double   openPrice;
   datetime openTime;
   long     openTimeMs;
  };

double   g_equityAtAttach = 0.0;
TradeActionRow g_tradeActions[];
int      g_tradeActionCount = 0;
OpenTicketSnapshot g_openTicketSnapshot[];
int      g_openTicketSnapshotCount = 0;
OpenTicketSnapshot g_pendingCloseSnapshot[];
int      g_pendingCloseSnapshotCount = 0;
double   g_tradeActionExposureBaseline = 0.0;

void   DrawTable();
double GetExposure(double currentExposure = 0.0, int orderType = -1, double lots = 0.0);
string ResolveTradeDirection(int ticketType, bool isCloseAction);
string ResolveTicketDirection(int ticketType);
void   ResetTradeActionStorage();
void   AppendTradeAction(const TradeActionRow &action);
bool   IsTrackableTicketType(int orderType);
void   ResetOpenTicketSnapshotStorage();
void   ResetPendingCloseStorage();
int    CaptureOpenTicketSnapshot(OpenTicketSnapshot &snapshot[]);
bool   SnapshotContainsTicket(OpenTicketSnapshot &snapshot[], int count, int ticket);
bool   PendingCloseContainsTicket(int ticket);
void   AddPendingCloseSnapshot(const OpenTicketSnapshot &snapshot);
void   AppendOpenActionFromSnapshot(const OpenTicketSnapshot &snapshot);
int    AppendNewOpenActionsFromSnapshotDiff(OpenTicketSnapshot &previousSnapshot[], int previousCount, OpenTicketSnapshot &latestSnapshot[], int latestCount);
bool   TryGetClosedOrderDetailsFromHistory(const OpenTicketSnapshot &snapshot,
                                           int &ticketType,
                                           datetime &closeTime,
                                           long &closeTimeMs,
                                           double &closePrice,
                                           double &realizedProfit);
bool   AppendCloseActionFromSnapshot(const OpenTicketSnapshot &snapshot);
int    AppendClosedActionsFromSnapshotDiff(OpenTicketSnapshot &previousSnapshot[],
                                           int previousCount,
                                           OpenTicketSnapshot &latestSnapshot[],
                                           int latestCount,
                                           int &pendingQueuedCount);
int    ResolvePendingCloseActions();
void   RefreshOpenTicketSnapshot(bool detectNewOpenActions = false);
void   SortOpenTicketSnapshotByTime(OpenTicketSnapshot &snapshot[], int count);
void   SortTradeActionsByTime();
bool   TrimTradeActionLog(int maxActions);
double GetExposureAfterAction(double currentExposure, const TradeActionRow &action);
void   RecalculateTradeActionDerivedFieldsCore();
void   RecalculateTradeActionDerivedFields();
bool   HasOpenActionForTicket(int ticket);
bool   HasCloseActionForTicket(int ticket);
double GetOpenTicketFloatingProfit(int ticket);
void   SeedBaselineOpenActions();
void   ClearTable();
void   CreateRectangle(string name, int x, int y, int width, int height, color bgColor, color borderColor, int borderWidth = 1);
void   CreateTableLabel(string name, string text, int x, int y, color textColor, int fontSize, ENUM_ANCHOR_POINT anchor);
int    GetColumnWidth(int columnIndex);
string GetColumnTitle(int columnIndex);
int    GetContentWidth();
int    GetColumnStartX(int panelLeftX, int columnIndex);
string GetCellValue(int columnIndex,
                    string openOrClose,
                    string direction,
                    string execPrice,
                    string exposure,
                    string ticket,
                    string symbolName,
                    string ticketDirection,
                    string millisecondsSinceLastAction,
                    string priceDifferenceFromPrevious,
                    string profitSinceStart);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_equityAtAttach = AccountEquity();
   ResetTradeActionStorage();
   ResetPendingCloseStorage();
   RefreshOpenTicketSnapshot(false);
   SeedBaselineOpenActions();
   DrawTable();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ResetTradeActionStorage();
   ResetOpenTicketSnapshotStorage();
   ResetPendingCloseStorage();
   ClearTable();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   RefreshOpenTicketSnapshot(true);
   DrawTable();
  }

//+------------------------------------------------------------------+
//| Draw TradeActions table                                          |
//+------------------------------------------------------------------+
void DrawTable()
  {
   ClearTable();

   // Collect rows from retained action log window.
   // Display order is oldest->newest within the retained tail.
   string rowOpenOrClose[10];
   string rowDirection[10];
   string rowExecutionPrice[10];
   string rowExposure[10];
   string rowTicket[10];
   string rowSymbolName[10];
   string rowTicketDirection[10];
   string rowMillisecondsSinceLastAction[10];
   string rowPriceDifferenceFromPrevious[10];
   string rowProfitSinceStart[10];

   int displayedRows = 0;
   int startIndex = 0;
   if(g_tradeActionCount > TA_MAX_ROWS)
      startIndex = g_tradeActionCount - TA_MAX_ROWS;

   for(int actionIndex = startIndex; actionIndex < g_tradeActionCount && displayedRows < TA_MAX_ROWS; actionIndex++)
     {
      TradeActionRow action = g_tradeActions[actionIndex];
      rowOpenOrClose[displayedRows] = action.openOrClose;
      rowDirection[displayedRows] = action.tradeDirection;
      rowExecutionPrice[displayedRows] = DoubleToString(action.executionPrice, Digits);
      rowExposure[displayedRows] = DoubleToString(action.exposure, 2);
      rowTicket[displayedRows] = IntegerToString(action.ticket);
      rowSymbolName[displayedRows] = action.symbolName;
      rowTicketDirection[displayedRows] = action.ticketDirection;
      rowMillisecondsSinceLastAction[displayedRows] = DoubleToString(action.millisecondsSinceLastAction, 0);
      rowPriceDifferenceFromPrevious[displayedRows] = DoubleToString(action.priceDifferenceFromPrevious, Digits);
      rowProfitSinceStart[displayedRows] = DoubleToString(action.profitSinceStart, 2);

      displayedRows++;
     }

   bool noActions = (displayedRows == 0);
   if(noActions)
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
   if(noActions)
     {
      CreateTableLabel("TA_Row_Empty", "No trade actions recorded since attach", panelLeft + TA_PADDING_X + 4, bodyY + 3, InpEmptyTextColor, TA_FONT_SIZE, ANCHOR_LEFT_UPPER);
      return;
     }

   for(int row = 0; row < displayedRows; row++)
     {
      int rowY = bodyY + (row * TA_ROW_HEIGHT);

      for(int col = 0; col < COL_COUNT; col++)
        {
         string text = GetCellValue(col,
                             rowOpenOrClose[row],
                             rowDirection[row],
                             rowExecutionPrice[row],
                             rowExposure[row],
                             rowTicket[row],
                             rowSymbolName[row],
                             rowTicketDirection[row],
                             rowMillisecondsSinceLastAction[row],
                             rowPriceDifferenceFromPrevious[row],
                             rowProfitSinceStart[row]);
         int colStart = GetColumnStartX(panelLeft, col);
         int colWidth = GetColumnWidth(col);

         bool rightAlign = (col == 0 || col == 5 || col == 6 || col == 7 || col == 8 || col == 9);
         if(rightAlign)
            CreateTableLabel("TA_Cell_" + IntegerToString(row + 1) + "_" + IntegerToString(col + 1), text, colStart + colWidth - 4, rowY + 3, InpTextColor, TA_FONT_SIZE, ANCHOR_RIGHT_UPPER);
         else
            CreateTableLabel("TA_Cell_" + IntegerToString(row + 1) + "_" + IntegerToString(col + 1), text, colStart + 4, rowY + 3, InpTextColor, TA_FONT_SIZE, ANCHOR_LEFT_UPPER);
        }
     }
  }

//+------------------------------------------------------------------+
//| Canonical direction mapping for trade actions                    |
//+------------------------------------------------------------------+
string ResolveTradeDirection(int ticketType, bool isCloseAction)
  {
   if(ticketType == OP_BUY)
      return(isCloseAction ? "sell" : "buy");

   if(ticketType == OP_SELL)
      return(isCloseAction ? "buy" : "sell");

   return("");
  }

//+------------------------------------------------------------------+
//| Ticket direction text helper                                     |
//+------------------------------------------------------------------+
string ResolveTicketDirection(int ticketType)
  {
   if(ticketType == OP_BUY)
      return("BUY");

   if(ticketType == OP_SELL)
      return("SELL");

   return("");
  }

//+------------------------------------------------------------------+
//| TradeAction storage helpers                                      |
//+------------------------------------------------------------------+
void ResetTradeActionStorage()
  {
   ArrayResize(g_tradeActions, 0);
   g_tradeActionCount = 0;
   g_tradeActionExposureBaseline = 0.0;
  }

void AppendTradeAction(const TradeActionRow &action)
  {
   int newSize = ArraySize(g_tradeActions) + 1;
   if(ArrayResize(g_tradeActions, newSize) != newSize)
      return;

   g_tradeActions[newSize - 1] = action;
   g_tradeActionCount = newSize;
  }

//+------------------------------------------------------------------+
//| Open ticket snapshot helpers                                     |
//+------------------------------------------------------------------+
bool IsTrackableTicketType(int orderType)
  {
   return(orderType == OP_BUY || orderType == OP_SELL);
  }

void ResetOpenTicketSnapshotStorage()
  {
   ArrayResize(g_openTicketSnapshot, 0);
   g_openTicketSnapshotCount = 0;
  }

void ResetPendingCloseStorage()
  {
   ArrayResize(g_pendingCloseSnapshot, 0);
   g_pendingCloseSnapshotCount = 0;
  }

int CaptureOpenTicketSnapshot(OpenTicketSnapshot &snapshot[])
  {
   ArrayResize(snapshot, 0);

   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      //if(OrderSymbol() != Symbol())
        // continue;

      int orderType = OrderType();
      if(!IsTrackableTicketType(orderType))
         continue;

      OpenTicketSnapshot item;
      item.ticket = OrderTicket();
      item.ticketType = orderType;
      item.lots = OrderLots();
      item.symbolName = OrderSymbol();
      item.openPrice = OrderOpenPrice();
      item.openTime = OrderOpenTime();
      item.openTimeMs = (long)item.openTime * 1000;

      int newSize = ArraySize(snapshot) + 1;
      if(ArrayResize(snapshot, newSize) != newSize)
         break;

      snapshot[newSize - 1] = item;
     }

   return(ArraySize(snapshot));
  }

bool SnapshotContainsTicket(OpenTicketSnapshot &snapshot[], int count, int ticket)
  {
   for(int i = 0; i < count; i++)
     {
      if(snapshot[i].ticket == ticket)
         return(true);
     }

   return(false);
  }

bool PendingCloseContainsTicket(int ticket)
  {
   for(int i = 0; i < g_pendingCloseSnapshotCount; i++)
     {
      if(g_pendingCloseSnapshot[i].ticket == ticket)
         return(true);
     }

   return(false);
  }

void AddPendingCloseSnapshot(const OpenTicketSnapshot &snapshot)
  {
   if(PendingCloseContainsTicket(snapshot.ticket))
      return;

   int newSize = ArraySize(g_pendingCloseSnapshot) + 1;
   if(ArrayResize(g_pendingCloseSnapshot, newSize) != newSize)
      return;

   g_pendingCloseSnapshot[newSize - 1] = snapshot;
   g_pendingCloseSnapshotCount = newSize;
  }

void AppendOpenActionFromSnapshot(const OpenTicketSnapshot &snapshot)
  {
   if(HasOpenActionForTicket(snapshot.ticket))
      return;

   TradeActionRow action;
   action.ticket = snapshot.ticket;
   action.openOrClose = TA_ACTION_OPEN;
   action.symbolName = snapshot.symbolName;
   action.tradeDirection = ResolveTradeDirection(snapshot.ticketType, false);
   action.executionPrice = snapshot.openPrice;
   action.lots = snapshot.lots;

   double previousExposure = 0.0;
   long previousActionTimeMs = 0;
   double previousExecutionPrice = 0.0;
   if(g_tradeActionCount > 0)
     {
      previousExposure = g_tradeActions[g_tradeActionCount - 1].exposure;
      previousActionTimeMs = g_tradeActions[g_tradeActionCount - 1].actionTimeMs;
      previousExecutionPrice = g_tradeActions[g_tradeActionCount - 1].executionPrice;
     }

   action.exposure = GetExposure(previousExposure, snapshot.ticketType, snapshot.lots);
   action.profit = GetOpenTicketFloatingProfit(snapshot.ticket);
   action.ticketDirection = ResolveTicketDirection(snapshot.ticketType);
   action.millisecondsSinceLastAction = 0;
   if(previousActionTimeMs > 0 && snapshot.openTimeMs >= previousActionTimeMs)
      action.millisecondsSinceLastAction = snapshot.openTimeMs - previousActionTimeMs;

   action.priceDifferenceFromPrevious = 0.0;
   if(g_tradeActionCount > 0)
      action.priceDifferenceFromPrevious = snapshot.openPrice - previousExecutionPrice;

   action.profitSinceStart = AccountEquity() - g_equityAtAttach;
   action.actionTime = snapshot.openTime;
   action.actionTimeMs = snapshot.openTimeMs;
   action.ticketType = snapshot.ticketType;

   AppendTradeAction(action);
  }

int AppendNewOpenActionsFromSnapshotDiff(OpenTicketSnapshot &previousSnapshot[], int previousCount, OpenTicketSnapshot &latestSnapshot[], int latestCount)
  {
   int appendedCount = 0;

   for(int i = 0; i < latestCount; i++)
     {
      OpenTicketSnapshot snapshot = latestSnapshot[i];
      if(SnapshotContainsTicket(previousSnapshot, previousCount, snapshot.ticket))
         continue;

      if(HasOpenActionForTicket(snapshot.ticket))
         continue;

      AppendOpenActionFromSnapshot(snapshot);
      appendedCount++;
     }

   return(appendedCount);
  }

bool TryGetClosedOrderDetailsFromHistory(const OpenTicketSnapshot &snapshot,
                                         int &ticketType,
                                         datetime &closeTime,
                                         long &closeTimeMs,
                                         double &closePrice,
                                         double &realizedProfit)
  {
   if(!OrderSelect(snapshot.ticket, SELECT_BY_TICKET, MODE_HISTORY))
      return(false);

   if(OrderSymbol() != snapshot.symbolName)
      return(false);

   ticketType = OrderType();
   if(!IsTrackableTicketType(ticketType))
      return(false);

   closeTime = OrderCloseTime();
   if(closeTime <= 0)
      return(false);

   closeTimeMs = (long)closeTime * 1000;
   closePrice = OrderClosePrice();
   realizedProfit = OrderProfit() + OrderSwap() + OrderCommission();

   return(true);
  }

bool AppendCloseActionFromSnapshot(const OpenTicketSnapshot &snapshot)
  {
   if(HasCloseActionForTicket(snapshot.ticket))
      return(true);

   int historyTicketType = -1;
   datetime closeTime = 0;
   long closeTimeMs = 0;
   double closePrice = 0.0;
   double realizedProfit = 0.0;
   if(!TryGetClosedOrderDetailsFromHistory(snapshot,
                                           historyTicketType,
                                           closeTime,
                                           closeTimeMs,
                                           closePrice,
                                           realizedProfit))
      return(false);

   TradeActionRow action;
   action.ticket = snapshot.ticket;
   action.openOrClose = TA_ACTION_CLOSE;
   action.symbolName = snapshot.symbolName;
   action.tradeDirection = ResolveTradeDirection(historyTicketType, true);
   action.executionPrice = closePrice;
   action.lots = snapshot.lots;

   double previousExposure = 0.0;
   long previousActionTimeMs = 0;
   double previousExecutionPrice = 0.0;
   if(g_tradeActionCount > 0)
     {
      previousExposure = g_tradeActions[g_tradeActionCount - 1].exposure;
      previousActionTimeMs = g_tradeActions[g_tradeActionCount - 1].actionTimeMs;
      previousExecutionPrice = g_tradeActions[g_tradeActionCount - 1].executionPrice;
     }

   if(historyTicketType == OP_BUY)
      action.exposure = previousExposure - snapshot.lots;
   else if(historyTicketType == OP_SELL)
      action.exposure = previousExposure + snapshot.lots;
   else
      action.exposure = previousExposure;

   action.profit = realizedProfit;
   action.ticketDirection = ResolveTicketDirection(historyTicketType);
   action.millisecondsSinceLastAction = 0;
   if(previousActionTimeMs > 0 && closeTimeMs >= previousActionTimeMs)
      action.millisecondsSinceLastAction = closeTimeMs - previousActionTimeMs;

   action.priceDifferenceFromPrevious = 0.0;
   if(g_tradeActionCount > 0)
      action.priceDifferenceFromPrevious = closePrice - previousExecutionPrice;

   action.profitSinceStart = AccountEquity() - g_equityAtAttach;
   action.actionTime = closeTime;
   action.actionTimeMs = closeTimeMs;
   action.ticketType = historyTicketType;

   AppendTradeAction(action);
   return(true);
  }

int AppendClosedActionsFromSnapshotDiff(OpenTicketSnapshot &previousSnapshot[],
                                        int previousCount,
                                        OpenTicketSnapshot &latestSnapshot[],
                                        int latestCount,
                                        int &pendingQueuedCount)
  {
   int appendedCount = 0;
   pendingQueuedCount = 0;

   for(int i = 0; i < previousCount; i++)
     {
      OpenTicketSnapshot snapshot = previousSnapshot[i];
      if(SnapshotContainsTicket(latestSnapshot, latestCount, snapshot.ticket))
         continue;

      if(HasCloseActionForTicket(snapshot.ticket))
         continue;

      if(AppendCloseActionFromSnapshot(snapshot))
        {
         appendedCount++;
         continue;
        }

      if(!PendingCloseContainsTicket(snapshot.ticket))
        {
         AddPendingCloseSnapshot(snapshot);
         pendingQueuedCount++;
        }
     }

   return(appendedCount);
  }

int ResolvePendingCloseActions()
  {
   if(g_pendingCloseSnapshotCount <= 0)
      return(0);

   int appendedCount = 0;
   OpenTicketSnapshot unresolved[];
   int unresolvedCount = 0;

   for(int i = 0; i < g_pendingCloseSnapshotCount; i++)
     {
      OpenTicketSnapshot snapshot = g_pendingCloseSnapshot[i];

      if(HasCloseActionForTicket(snapshot.ticket))
         continue;

      if(AppendCloseActionFromSnapshot(snapshot))
        {
         appendedCount++;
         continue;
        }

      int newSize = unresolvedCount + 1;
      if(ArrayResize(unresolved, newSize) != newSize)
         continue;

      unresolved[newSize - 1] = snapshot;
      unresolvedCount = newSize;
     }

   if(ArrayResize(g_pendingCloseSnapshot, unresolvedCount) != unresolvedCount)
     {
      ResetPendingCloseStorage();
      return(appendedCount);
     }

   for(int i = 0; i < unresolvedCount; i++)
      g_pendingCloseSnapshot[i] = unresolved[i];

   g_pendingCloseSnapshotCount = unresolvedCount;
   return(appendedCount);
  }

void RefreshOpenTicketSnapshot(bool detectNewOpenActions)
  {
   OpenTicketSnapshot latest[];
   int count = CaptureOpenTicketSnapshot(latest);
   if(count > 1)
      SortOpenTicketSnapshotByTime(latest, count);

   int appendedOpenCount = 0;
   int appendedCloseCount = 0;
   int pendingQueuedCount = 0;
   int resolvedPendingCount = 0;
   if(detectNewOpenActions)
     {
      appendedOpenCount = AppendNewOpenActionsFromSnapshotDiff(g_openTicketSnapshot, g_openTicketSnapshotCount, latest, count);
      appendedCloseCount = AppendClosedActionsFromSnapshotDiff(g_openTicketSnapshot,
                                                               g_openTicketSnapshotCount,
                                                               latest,
                                                               count,
                                                               pendingQueuedCount);
     }

   if(ArrayResize(g_openTicketSnapshot, count) != count)
     {
      ResetOpenTicketSnapshotStorage();
      return;
     }

   for(int i = 0; i < count; i++)
      g_openTicketSnapshot[i] = latest[i];

   g_openTicketSnapshotCount = count;

   if(detectNewOpenActions)
      resolvedPendingCount = ResolvePendingCloseActions();

   RecalculateTradeActionDerivedFields();

   if(appendedOpenCount > 0)
      PrintFormat("TradeAction: detected %d new open action(s).", appendedOpenCount);

   if(appendedCloseCount > 0)
      PrintFormat("TradeAction: detected %d close action(s) from snapshot diff.", appendedCloseCount);

   if(resolvedPendingCount > 0)
      PrintFormat("TradeAction: resolved %d pending close action(s).", resolvedPendingCount);

   if(pendingQueuedCount > 0)
      PrintFormat("TradeAction: queued %d pending close action(s) waiting for history.", pendingQueuedCount);
  }

void SortOpenTicketSnapshotByTime(OpenTicketSnapshot &snapshot[], int count)
  {
   for(int i = 1; i < count; i++)
     {
      OpenTicketSnapshot key = snapshot[i];
      int j = i - 1;

      while(j >= 0)
        {
         bool shouldShift = (snapshot[j].openTimeMs > key.openTimeMs);
         if(snapshot[j].openTimeMs == key.openTimeMs && snapshot[j].ticket > key.ticket)
            shouldShift = true;

         if(!shouldShift)
            break;

         snapshot[j + 1] = snapshot[j];
         j--;
        }

      snapshot[j + 1] = key;
     }
  }

void SortTradeActionsByTime()
  {
   // Deterministic chronological order:
   // 1) older actionTimeMs first
   // 2) for same timestamp: open before close
   // 3) then lower ticket first
   for(int i = 1; i < g_tradeActionCount; i++)
     {
      TradeActionRow key = g_tradeActions[i];
      int j = i - 1;

      while(j >= 0)
        {
         bool shouldShift = (g_tradeActions[j].actionTimeMs > key.actionTimeMs);
         if(g_tradeActions[j].actionTimeMs == key.actionTimeMs)
           {
            bool currentIsClose = (g_tradeActions[j].openOrClose == TA_ACTION_CLOSE);
            bool keyIsClose = (key.openOrClose == TA_ACTION_CLOSE);

            if(currentIsClose && !keyIsClose)
               shouldShift = true;
            else if(currentIsClose == keyIsClose && g_tradeActions[j].ticket > key.ticket)
               shouldShift = true;
           }

         if(!shouldShift)
            break;

         g_tradeActions[j + 1] = g_tradeActions[j];
         j--;
        }

      g_tradeActions[j + 1] = key;
     }
  }

bool TrimTradeActionLog(int maxActions)
  {
   if(maxActions <= 0 || g_tradeActionCount <= maxActions)
      return(false);

   int dropCount = g_tradeActionCount - maxActions;
   if(dropCount <= 0)
      return(false);

   double newExposureBaseline = g_tradeActions[dropCount - 1].exposure;
   TradeActionRow retained[];
   if(ArrayResize(retained, maxActions) != maxActions)
      return(false);

   for(int i = 0; i < maxActions; i++)
      retained[i] = g_tradeActions[dropCount + i];

   if(ArrayResize(g_tradeActions, maxActions) != maxActions)
      return(false);

   for(int i = 0; i < maxActions; i++)
      g_tradeActions[i] = retained[i];

   g_tradeActionExposureBaseline = newExposureBaseline;
   g_tradeActionCount = maxActions;
   return(true);
  }

double GetExposureAfterAction(double currentExposure, const TradeActionRow &action)
  {
   double lots = action.lots;
   if(lots < 0.0)
      lots = -lots;

   if(action.openOrClose == TA_ACTION_OPEN)
      return(GetExposure(currentExposure, action.ticketType, lots));

   if(action.openOrClose == TA_ACTION_CLOSE)
     {
      if(action.ticketType == OP_BUY)
         return(currentExposure - lots);

      if(action.ticketType == OP_SELL)
         return(currentExposure + lots);
     }

   return(currentExposure);
  }

void RecalculateTradeActionDerivedFieldsCore()
  {
   if(g_tradeActionCount <= 0)
      return;

   double runningExposure = g_tradeActionExposureBaseline;
   long previousActionTimeMs = 0;
   double previousExecutionPrice = 0.0;
   double profitSinceAttach = AccountEquity() - g_equityAtAttach;

   for(int i = 0; i < g_tradeActionCount; i++)
     {
      TradeActionRow action = g_tradeActions[i];
      action.exposure = GetExposureAfterAction(runningExposure, action);
      runningExposure = action.exposure;

      action.millisecondsSinceLastAction = 0;
      if(previousActionTimeMs > 0 && action.actionTimeMs >= previousActionTimeMs)
         action.millisecondsSinceLastAction = action.actionTimeMs - previousActionTimeMs;

      action.priceDifferenceFromPrevious = 0.0;
      if(i > 0)
         action.priceDifferenceFromPrevious = action.executionPrice - previousExecutionPrice;

      action.profitSinceStart = profitSinceAttach;
      g_tradeActions[i] = action;

      previousActionTimeMs = action.actionTimeMs;
      previousExecutionPrice = action.executionPrice;
     }
  }

void RecalculateTradeActionDerivedFields()
  {
   if(g_tradeActionCount <= 0)
      return;

   SortTradeActionsByTime();
   RecalculateTradeActionDerivedFieldsCore();

   // Bounded retention keeps UI/object churn stable on heavy activity.
   if(TrimTradeActionLog(TA_ACTION_LOG_RETENTION))
      RecalculateTradeActionDerivedFieldsCore();
  }

bool HasOpenActionForTicket(int ticket)
  {
   for(int i = 0; i < g_tradeActionCount; i++)
     {
      if(g_tradeActions[i].ticket == ticket && g_tradeActions[i].openOrClose == TA_ACTION_OPEN)
         return(true);
     }

   return(false);
  }

bool HasCloseActionForTicket(int ticket)
  {
   for(int i = 0; i < g_tradeActionCount; i++)
     {
      if(g_tradeActions[i].ticket == ticket && g_tradeActions[i].openOrClose == TA_ACTION_CLOSE)
         return(true);
     }

   return(false);
  }

double GetOpenTicketFloatingProfit(int ticket)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return(0.0);

   if(!IsTrackableTicketType(OrderType()))
      return(0.0);

   return(OrderProfit() + OrderSwap() + OrderCommission());
  }

void SeedBaselineOpenActions()
  {
   if(g_openTicketSnapshotCount <= 0)
      return;

   if(g_tradeActionCount > 0)
      return;

   OpenTicketSnapshot ordered[];
   int snapshotCount = g_openTicketSnapshotCount;
   if(ArrayResize(ordered, snapshotCount) != snapshotCount)
      return;

   for(int i = 0; i < snapshotCount; i++)
      ordered[i] = g_openTicketSnapshot[i];

   SortOpenTicketSnapshotByTime(ordered, snapshotCount);

   double runningExposure = 0.0;
   long previousActionTimeMs = 0;
   double previousExecutionPrice = 0.0;
   double profitSinceAttach = AccountEquity() - g_equityAtAttach;
   int seededCount = 0;

   for(int i = 0; i < snapshotCount; i++)
     {
      OpenTicketSnapshot snapshot = ordered[i];
      if(HasOpenActionForTicket(snapshot.ticket))
         continue;

      TradeActionRow action;
      action.ticket = snapshot.ticket;
      action.openOrClose = TA_ACTION_OPEN;
      action.symbolName = snapshot.symbolName;
      action.tradeDirection = ResolveTradeDirection(snapshot.ticketType, false);
      action.executionPrice = snapshot.openPrice;
      action.lots = snapshot.lots;
      runningExposure = GetExposure(runningExposure, snapshot.ticketType, snapshot.lots);
      action.exposure = runningExposure;
      action.profit = GetOpenTicketFloatingProfit(snapshot.ticket);
      action.ticketDirection = ResolveTicketDirection(snapshot.ticketType);
      action.millisecondsSinceLastAction = 0;
      if(previousActionTimeMs > 0 && snapshot.openTimeMs >= previousActionTimeMs)
         action.millisecondsSinceLastAction = snapshot.openTimeMs - previousActionTimeMs;
      action.priceDifferenceFromPrevious = 0.0;
      if(seededCount > 0)
         action.priceDifferenceFromPrevious = snapshot.openPrice - previousExecutionPrice;
      action.profitSinceStart = profitSinceAttach;
      action.actionTime = snapshot.openTime;
      action.actionTimeMs = snapshot.openTimeMs;
      action.ticketType = snapshot.ticketType;

      AppendTradeAction(action);
      previousActionTimeMs = snapshot.openTimeMs;
      previousExecutionPrice = snapshot.openPrice;
      seededCount++;
     }

   if(seededCount > 0)
      PrintFormat("TradeAction: Seeded %d baseline open actions.", seededCount);

   RecalculateTradeActionDerivedFields();
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
      case 0: return(COL_W_TICKET);
      case 1: return(COL_W_SYMBOL_NAME);
      case 2: return(COL_W_OPEN_CLOSE);
      case 3: return(COL_W_DIRECTION);
      case 4: return(COL_W_TICKET_DIRECTION);
      case 5: return(COL_W_EXEC_PRICE);
      case 6: return(COL_W_EXPOSURE);
      case 7: return(COL_W_MILLISECONDS_SINCE_LAST);
      case 8: return(COL_W_PRICE_DIFF_FROM_PREVIOUS);
      case 9: return(COL_W_PROFIT_SINCE_START);
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
      case 0: return("Ticket");
      case 1: return("SymbolName");
      case 2: return("OpenOrClose");
      case 3: return("TradeDirection");
      case 4: return("TicketDirection");
      case 5: return("ExecutionPrice");
      case 6: return("Exposure");
      case 7: return("MillisecondsSinceLastAction");
      case 8: return("PriceDifferenceFromPrevious");
      case 9: return("ProfitSinceStart");
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
string GetCellValue(int columnIndex,
                    string openOrClose,
                    string direction,
                    string execPrice,
                    string exposure,
                    string ticket,
                    string symbolName,
                    string ticketDirection,
                    string millisecondsSinceLastAction,
                    string priceDifferenceFromPrevious,
                    string profitSinceStart)
  {
   switch(columnIndex)
     {
      case 0: return(ticket);
      case 1: return(symbolName);
      case 2: return(openOrClose);
      case 3: return(direction);
      case 4: return(ticketDirection);
      case 5: return(execPrice);
      case 6: return(exposure);
      case 7: return(millisecondsSinceLastAction);
      case 8: return(priceDifferenceFromPrevious);
      case 9: return(profitSinceStart);
     }
   return("");
  }
//+------------------------------------------------------------------+
