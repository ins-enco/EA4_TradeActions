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
input int   InpRefreshIntervalMs    = 200;
input int   InpVisibleRows          = 10;

// Table layout
string TA_PREFIX         = "TA_";
int    TA_RIGHT_MARGIN   = 14;
int    TA_TOP_MARGIN     = 14;
int    TA_PADDING_X      = 8;
int    TA_PADDING_Y      = 8;
int    TA_TITLE_HEIGHT   = 22;
int    TA_HEADER_HEIGHT  = 20;
int    TA_ROW_HEIGHT     = 19;
int    TA_FONT_SIZE      = 9;
string TA_FONT_NAME      = "Tahoma";
int    TA_VISIBLE_ROWS_DEFAULT = 10;
int    TA_VISIBLE_ROWS_MIN     = 1;
int    TA_VISIBLE_ROWS_MAX     = 50;
int    TA_SCROLL_BUTTON_WIDTH  = 28;
int    TA_SCROLL_BUTTON_GAP    = 4;

// Column widths (pixels)
int COL_COUNT                        = 11;
int COL_W_OPEN_CLOSE                 = 95;
int COL_W_DIRECTION                  = 95;
int COL_W_EXEC_PRICE                 = 95;
int COL_W_EXPOSURE                   = 80;
int COL_W_MEASURED_TIMESTAMP         = 170;
int COL_W_TICKET                     = 90;
int COL_W_SYMBOL_NAME                = 95;
int COL_W_TICKET_DIRECTION           = 110;
int COL_W_MILLISECONDS_SINCE_LAST    = 160;
int COL_W_PRICE_DIFF_FROM_PREVIOUS   = 170;
int COL_W_PROFIT_SINCE_START         = 130;
int TA_ACTION_LOG_RETENTION          = 200;

string TA_ACTION_OPEN  = "Open";
string TA_ACTION_CLOSE = "Close";
int    TA_DERIVED_DECIMALS = 10;
double TA_EXPOSURE_EPSILON = 0.000001;
string TA_VALUE_NOT_AVAILABLE = "";
int    TA_REFRESH_INTERVAL_MS_MIN = 10;
int    TA_REFRESH_INTERVAL_MS_MAX = 5000;
int    TA_REFRESH_INTERVAL_MS_DEFAULT = 200;

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
   bool     hasPriceDifferenceFromPrevious;
   double   profitSinceStart;
   datetime actionTime;
   long     actionTimeMs;
   bool     hasMeasuredTimestamp;
   datetime measuredTimestampLocal;
   long     measuredTimestampMs;
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

struct TradeActionSymbolState
  {
   string   symbolName;
   bool     hasPreviousAction;
   string   tradeDirection;
   long     actionTimeMs;
   double   executionPrice;
   double   exposure;
   double   profitSinceStart;
   bool     hasMeasuredTimestamp;
   long     measuredTimestampMs;
  };

TradeActionRow g_tradeActions[];
int      g_tradeActionCount = 0;
OpenTicketSnapshot g_openTicketSnapshot[];
int      g_openTicketSnapshotCount = 0;
OpenTicketSnapshot g_pendingCloseSnapshot[];
int      g_pendingCloseSnapshotCount = 0;
TradeActionSymbolState g_tradeActionSymbolBaselines[];
int      g_tradeActionSymbolBaselineCount = 0;
int      g_refreshIntervalMs = 0;
int      g_visibleRows = 0;
int      g_tableScrollOffset = 0;
bool     g_refreshTimerStarted = false;
bool     g_refreshInProgress = false;
bool     g_timerLagLogged = false;
bool     g_timerOverrunLogged = false;
ulong    g_lastTimerRunUs = 0;
string   g_lastTableRenderState = "";
bool     g_hasRenderedTable = false;

int    NormalizeRefreshIntervalMs(int requestedIntervalMs);
int    NormalizeVisibleRows(int requestedVisibleRows);
int    GetTableChartWidth();
int    GetTableChartHeight();
int    GetTableVisibleRows();
int    GetTableScrollOffsetMax();
int    GetTableWindowStartIndex();
void   ClampTableScrollOffset();
bool   TableHasHiddenRows();
string GetTableViewportStatusText(int displayedRows);
void   ClearMeasuredTimestamp(TradeActionRow &action);
void   SetMeasuredTimestampNow(TradeActionRow &action);
long   GetTradeActionSortTimeMs(const TradeActionRow &action);
string BuildTableRenderState();
void   ResetTableRenderState();
void   RedrawTableNow();
bool   StartRefreshTimer();
void   StopRefreshTimer();
void   RefreshTradeActionView(bool detectNewOpenActions, bool seedBaseline, bool redrawTable);
void   RunTimerRefreshCycle();
void   DrawTable();
void   ScrollTableBy(int deltaRows);
void   ScrollTableToBoundary(bool toOldest);
string ResolveTradeDirection(int ticketType, bool isCloseAction);
string ResolveTicketDirection(int ticketType);
void   ResetTradeActionStorage();
void   ResetTradeActionBaselineStorage();
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
double GetSignedQuantity(string tradeDirection, double lots);
double RoundTradeActionValue(double value);
bool   IsOppositeTradeDirection(string currentDirection, string previousDirection);
int    FindTradeActionSymbolStateIndex(TradeActionSymbolState &states[], int count, string symbolName);
int    EnsureTradeActionSymbolState(TradeActionSymbolState &states[], int &count, string symbolName);
void   CopyTradeActionSymbolBaselines(TradeActionSymbolState &states[], int &count);
void   UpdateTradeActionSymbolStateFromAction(TradeActionSymbolState &state, const TradeActionRow &action);
void   RecalculateTradeActionDerivedFieldsCore();
void   RecalculateTradeActionDerivedFields();
bool   HasOpenActionForTicket(int ticket);
bool   HasCloseActionForTicket(int ticket);
double GetOpenTicketFloatingProfit(int ticket);
void   SeedBaselineOpenActions();
string FormatMeasuredTimestamp(const TradeActionRow &action);
string FormatPriceDifferenceFromPrevious(const TradeActionRow &action);
string FormatProfitSinceStart(const TradeActionRow &action);
void   ClearTable();
void   CreateRectangle(string name, int x, int y, int width, int height, color bgColor, color borderColor, int borderWidth = 1);
void   CreateTableLabel(string name, string text, int x, int y, color textColor, int fontSize, ENUM_ANCHOR_POINT anchor);
void   CreateTableButton(string name, string text, int x, int y, int width, int height, bool enabled);
int    GetColumnWidth(int columnIndex);
string GetColumnTitle(int columnIndex);
int    GetContentWidth();
int    GetColumnStartX(int panelLeftX, int columnIndex);
string GetCellValue(int columnIndex,
                    string openOrClose,
                    string direction,
                    string execPrice,
                    string exposure,
                    string measuredTimestamp,
                    string ticket,
                    string symbolName,
                    string ticketDirection,
                    string millisecondsSinceLastAction,
                    string priceDifferenceFromPrevious,
                    string profitSinceStart);

int NormalizeRefreshIntervalMs(int requestedIntervalMs)
  {
   int intervalMs = requestedIntervalMs;
   if(intervalMs <= 0)
      intervalMs = TA_REFRESH_INTERVAL_MS_DEFAULT;

   if(intervalMs < TA_REFRESH_INTERVAL_MS_MIN)
      intervalMs = TA_REFRESH_INTERVAL_MS_MIN;

   if(intervalMs > TA_REFRESH_INTERVAL_MS_MAX)
      intervalMs = TA_REFRESH_INTERVAL_MS_MAX;

   return(intervalMs);
  }

int NormalizeVisibleRows(int requestedVisibleRows)
  {
   int visibleRows = requestedVisibleRows;
   if(visibleRows <= 0)
      visibleRows = TA_VISIBLE_ROWS_DEFAULT;

   if(visibleRows < TA_VISIBLE_ROWS_MIN)
      visibleRows = TA_VISIBLE_ROWS_MIN;

   if(visibleRows > TA_VISIBLE_ROWS_MAX)
      visibleRows = TA_VISIBLE_ROWS_MAX;

   return(visibleRows);
  }

int GetTableChartWidth()
  {
   int chartWidth = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   if(chartWidth <= 0)
      chartWidth = 800;

   return(chartWidth);
  }

int GetTableChartHeight()
  {
   int chartHeight = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(chartHeight <= 0)
      chartHeight = 600;

   return(chartHeight);
  }

int GetTableVisibleRows()
  {
   int desiredRows = g_visibleRows;
   if(desiredRows <= 0)
      desiredRows = TA_VISIBLE_ROWS_DEFAULT;

   int availableHeight = GetTableChartHeight() - TA_TOP_MARGIN - (TA_PADDING_Y * 2) - TA_TITLE_HEIGHT - TA_HEADER_HEIGHT - 12;
   int maxRowsByChart = availableHeight / TA_ROW_HEIGHT;
   if(maxRowsByChart < 1)
      maxRowsByChart = 1;

   if(desiredRows > maxRowsByChart)
      return(maxRowsByChart);

   return(desiredRows);
  }

int GetTableScrollOffsetMax()
  {
   int hiddenRows = g_tradeActionCount - GetTableVisibleRows();
   if(hiddenRows < 0)
      hiddenRows = 0;

   return(hiddenRows);
  }

void ClampTableScrollOffset()
  {
   if(g_tableScrollOffset < 0)
      g_tableScrollOffset = 0;

   int maxOffset = GetTableScrollOffsetMax();
   if(g_tableScrollOffset > maxOffset)
      g_tableScrollOffset = maxOffset;
  }

int GetTableWindowStartIndex()
  {
   ClampTableScrollOffset();

   int visibleRows = GetTableVisibleRows();
   int startIndex = g_tradeActionCount - visibleRows - g_tableScrollOffset;
   if(startIndex < 0)
      startIndex = 0;

   return(startIndex);
  }

bool TableHasHiddenRows()
  {
   return(g_tradeActionCount > GetTableVisibleRows());
  }

string GetTableViewportStatusText(int displayedRows)
  {
   if(g_tradeActionCount <= 0 || displayedRows <= 0)
      return("0/0");

   int startIndex = GetTableWindowStartIndex();
   int endIndex = startIndex + displayedRows;
   return(StringFormat("%d-%d/%d", startIndex + 1, endIndex, g_tradeActionCount));
  }

void ClearMeasuredTimestamp(TradeActionRow &action)
  {
   action.hasMeasuredTimestamp = false;
   action.measuredTimestampLocal = 0;
   action.measuredTimestampMs = 0;
  }

void SetMeasuredTimestampNow(TradeActionRow &action)
  {
   datetime localTime = TimeLocal();
   long millisecondsPart = (long)(GetTickCount() % 1000);

   action.hasMeasuredTimestamp = true;
   action.measuredTimestampLocal = localTime;
   action.measuredTimestampMs = ((long)localTime * 1000) + millisecondsPart;
  }

long GetTradeActionSortTimeMs(const TradeActionRow &action)
  {
   // Keep table ordering on broker event time; measured timestamps remain display-only.
   return(action.actionTimeMs);
  }

string BuildTableRenderState()
  {
   int chartWidth = GetTableChartWidth();
   int chartHeight = GetTableChartHeight();
   int visibleRows = GetTableVisibleRows();
   ClampTableScrollOffset();
   int displayedRows = 0;
   int startIndex = GetTableWindowStartIndex();

   string state = IntegerToString(chartWidth) + "|" + IntegerToString(chartHeight) + "|" + IntegerToString(visibleRows) + "|" + IntegerToString(g_tableScrollOffset) + "|" + IntegerToString(startIndex) + "|" + IntegerToString(g_tradeActionCount);

   for(int actionIndex = startIndex; actionIndex < g_tradeActionCount && displayedRows < visibleRows; actionIndex++)
     {
      TradeActionRow action = g_tradeActions[actionIndex];
      state += "|" + IntegerToString(action.ticket);
      state += "|" + action.openOrClose;
      state += "|" + action.symbolName;
      state += "|" + action.tradeDirection;
      state += "|" + action.ticketDirection;
      state += "|" + DoubleToString(action.executionPrice, Digits);
      state += "|" + DoubleToString(action.exposure, 2);
      state += "|" + FormatMeasuredTimestamp(action);
      state += "|" + DoubleToString(action.millisecondsSinceLastAction, 0);
      state += "|" + FormatPriceDifferenceFromPrevious(action);
      state += "|" + FormatProfitSinceStart(action);
      displayedRows++;
     }

   if(displayedRows == 0)
      state += "|empty";

   return(state);
  }

void ResetTableRenderState()
  {
   g_lastTableRenderState = "";
   g_hasRenderedTable = false;
  }

void RedrawTableNow()
  {
   string renderState = BuildTableRenderState();
   DrawTable();
   g_lastTableRenderState = renderState;
   g_hasRenderedTable = true;
   ChartRedraw(0);
  }

bool StartRefreshTimer()
  {
   StopRefreshTimer();
   ResetLastError();
   if(!EventSetMillisecondTimer(g_refreshIntervalMs))
     {
      PrintFormat("TradeAction: failed to start timer at %d ms (error %d).",
                  g_refreshIntervalMs,
                  GetLastError());
      g_refreshTimerStarted = false;
      return(false);
     }

   g_refreshTimerStarted = true;
   PrintFormat("TradeAction: started millisecond timer at %d ms.", g_refreshIntervalMs);
   return(true);
  }

void StopRefreshTimer()
  {
   if(!g_refreshTimerStarted)
      return;

   EventKillTimer();
   g_refreshTimerStarted = false;
   g_refreshInProgress = false;
   g_timerLagLogged = false;
   g_timerOverrunLogged = false;
   g_lastTimerRunUs = 0;
  }

void RefreshTradeActionView(bool detectNewOpenActions, bool seedBaseline, bool redrawTable)
  {
   RefreshOpenTicketSnapshot(detectNewOpenActions);

   if(seedBaseline)
      SeedBaselineOpenActions();

   if(redrawTable)
     {
      string renderState = BuildTableRenderState();
      bool missingTableObjects = (ObjectFind(0, "TA_Background") < 0);
      if(!g_hasRenderedTable || missingTableObjects || renderState != g_lastTableRenderState)
        {
         DrawTable();
         g_lastTableRenderState = renderState;
         g_hasRenderedTable = true;
        }
     }
  }

void RunTimerRefreshCycle()
  {
   if(g_refreshInProgress)
      return;

   ulong cycleStartUs = GetMicrosecondCount();
   if(g_lastTimerRunUs != 0)
     {
      ulong observedIntervalUs = cycleStartUs - g_lastTimerRunUs;
      if(observedIntervalUs > (ulong)g_refreshIntervalMs * 2000)
        {
         if(!g_timerLagLogged)
           {
            PrintFormat("TradeAction: timer cadence lagged to %.3f ms (target %d ms).",
                        (double)observedIntervalUs / 1000.0,
                        g_refreshIntervalMs);
            g_timerLagLogged = true;
           }
        }
      else
         g_timerLagLogged = false;
     }

   g_refreshInProgress = true;
   g_lastTimerRunUs = cycleStartUs;

   RefreshTradeActionView(true, false, true);

   ulong cycleDurationUs = GetMicrosecondCount() - cycleStartUs;
   g_refreshInProgress = false;

   if(cycleDurationUs > (ulong)g_refreshIntervalMs * 1000)
     {
      if(!g_timerOverrunLogged)
        {
         PrintFormat("TradeAction: timer refresh took %.3f ms (target %d ms).",
                     (double)cycleDurationUs / 1000.0,
                     g_refreshIntervalMs);
         g_timerOverrunLogged = true;
        }
     }
   else
      g_timerOverrunLogged = false;
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   ResetTradeActionStorage();
   ResetOpenTicketSnapshotStorage();
   ResetPendingCloseStorage();
   ResetTableRenderState();
   g_refreshIntervalMs = NormalizeRefreshIntervalMs(InpRefreshIntervalMs);
   g_visibleRows = NormalizeVisibleRows(InpVisibleRows);
   g_tableScrollOffset = 0;
   if(g_refreshIntervalMs != InpRefreshIntervalMs)
      PrintFormat("TradeAction: normalized refresh interval from %d ms to %d ms.",
                  InpRefreshIntervalMs,
                  g_refreshIntervalMs);
   if(g_visibleRows != InpVisibleRows)
      PrintFormat("TradeAction: normalized visible rows from %d to %d.",
                  InpVisibleRows,
                  g_visibleRows);

   RefreshTradeActionView(false, true, true);
   if(!StartRefreshTimer())
      return(INIT_FAILED);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   StopRefreshTimer();
   ResetTradeActionStorage();
   ResetOpenTicketSnapshotStorage();
   ResetPendingCloseStorage();
   g_tableScrollOffset = 0;
   ClearTable();
   ResetTableRenderState();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
  }

void OnTimer()
  {
   RunTimerRefreshCycle();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == "TA_ScrollOldest")
     {
      ScrollTableToBoundary(true);
      return;
     }

   if(sparam == "TA_ScrollOlder")
     {
      ScrollTableBy(1);
      return;
     }

   if(sparam == "TA_ScrollNewer")
     {
      ScrollTableBy(-1);
      return;
     }

   if(sparam == "TA_ScrollNewest")
      ScrollTableToBoundary(false);
  }

//+------------------------------------------------------------------+
//| Draw TradeActions table                                          |
//+------------------------------------------------------------------+
void DrawTable()
  {
   ClearTable();
   ClampTableScrollOffset();

   int visibleRows = GetTableVisibleRows();
   int displayedRows = 0;
   int startIndex = GetTableWindowStartIndex();

   if(g_tradeActionCount > startIndex)
      displayedRows = g_tradeActionCount - startIndex;

   if(displayedRows > visibleRows)
      displayedRows = visibleRows;

   bool noActions = (displayedRows == 0);
   int bodyRows = noActions ? 1 : displayedRows;

   int contentWidth = GetContentWidth();
   int panelWidth = contentWidth + (TA_PADDING_X * 2);
   int panelHeight = (TA_PADDING_Y * 2) + TA_TITLE_HEIGHT + TA_HEADER_HEIGHT + (bodyRows * TA_ROW_HEIGHT);

   int chartWidth = GetTableChartWidth();

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
   int gridHeight = TA_HEADER_HEIGHT + (bodyRows * TA_ROW_HEIGHT);
   int splitX = panelLeft + TA_PADDING_X;

   for(int c = 0; c < COL_COUNT - 1; c++)
     {
      splitX += GetColumnWidth(c);
      CreateRectangle("TA_VLine_" + IntegerToString(c + 1), splitX, gridTop, 1, gridHeight, InpGridColor, InpGridColor, 1);
     }

   CreateRectangle("TA_HLine_Header", panelLeft + TA_PADDING_X, bodyY, contentWidth, 1, InpGridColor, InpGridColor, 1);

   for(int r = 1; r < bodyRows; r++)
     {
      int yLine = bodyY + (r * TA_ROW_HEIGHT);
      CreateRectangle("TA_HLine_Row_" + IntegerToString(r), panelLeft + TA_PADDING_X, yLine, contentWidth, 1, InpGridColor, InpGridColor, 1);
     }

   // Title
   CreateTableLabel("TA_Title", "TradeActions", panelLeft + TA_PADDING_X + 2, titleY + 2, InpTitleColor, TA_FONT_SIZE + 1, ANCHOR_LEFT_UPPER);
   string viewportText = GetTableViewportStatusText(displayedRows);
   int titleRight = panelLeft + panelWidth - TA_PADDING_X - 4;
   if(TableHasHiddenRows())
     {
      int buttonHeight = TA_TITLE_HEIGHT - 4;
      int buttonsWidth = (TA_SCROLL_BUTTON_WIDTH * 4) + (TA_SCROLL_BUTTON_GAP * 3);
      int buttonsLeft = titleRight - buttonsWidth + 1;
      int maxOffset = GetTableScrollOffsetMax();
      bool canScrollOlder = (g_tableScrollOffset < maxOffset);
      bool canScrollNewer = (g_tableScrollOffset > 0);

      CreateTableButton("TA_ScrollOldest", "<<", buttonsLeft, titleY + 2, TA_SCROLL_BUTTON_WIDTH, buttonHeight, canScrollOlder);
      CreateTableButton("TA_ScrollOlder", "<", buttonsLeft + TA_SCROLL_BUTTON_WIDTH + TA_SCROLL_BUTTON_GAP, titleY + 2, TA_SCROLL_BUTTON_WIDTH, buttonHeight, canScrollOlder);
      CreateTableButton("TA_ScrollNewer", ">", buttonsLeft + ((TA_SCROLL_BUTTON_WIDTH + TA_SCROLL_BUTTON_GAP) * 2), titleY + 2, TA_SCROLL_BUTTON_WIDTH, buttonHeight, canScrollNewer);
      CreateTableButton("TA_ScrollNewest", ">>", buttonsLeft + ((TA_SCROLL_BUTTON_WIDTH + TA_SCROLL_BUTTON_GAP) * 3), titleY + 2, TA_SCROLL_BUTTON_WIDTH, buttonHeight, canScrollNewer);

      CreateTableLabel("TA_ViewStatus", viewportText, buttonsLeft - 6, titleY + 3, InpEmptyTextColor, TA_FONT_SIZE, ANCHOR_RIGHT_UPPER);
     }
   else
      CreateTableLabel("TA_ViewStatus", viewportText, titleRight, titleY + 3, InpEmptyTextColor, TA_FONT_SIZE, ANCHOR_RIGHT_UPPER);

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
      TradeActionRow action = g_tradeActions[startIndex + row];
      int rowY = bodyY + (row * TA_ROW_HEIGHT);

      for(int col = 0; col < COL_COUNT; col++)
        {
         string text = GetCellValue(col,
                             action.openOrClose,
                             action.tradeDirection,
                             DoubleToString(action.executionPrice, Digits),
                             DoubleToString(action.exposure, 2),
                             FormatMeasuredTimestamp(action),
                             IntegerToString(action.ticket),
                             action.symbolName,
                             action.ticketDirection,
                             DoubleToString(action.millisecondsSinceLastAction, 0),
                             FormatPriceDifferenceFromPrevious(action),
                             FormatProfitSinceStart(action));
         int colStart = GetColumnStartX(panelLeft, col);
         int colWidth = GetColumnWidth(col);

         bool rightAlign = (col == 0 || col == 5 || col == 6 || col == 8 || col == 9 || col == 10);
         if(rightAlign)
            CreateTableLabel("TA_Cell_" + IntegerToString(row + 1) + "_" + IntegerToString(col + 1), text, colStart + colWidth - 4, rowY + 3, InpTextColor, TA_FONT_SIZE, ANCHOR_RIGHT_UPPER);
         else
            CreateTableLabel("TA_Cell_" + IntegerToString(row + 1) + "_" + IntegerToString(col + 1), text, colStart + 4, rowY + 3, InpTextColor, TA_FONT_SIZE, ANCHOR_LEFT_UPPER);
        }
      }
  }

void ScrollTableBy(int deltaRows)
  {
   if(deltaRows == 0)
      return;

   int previousOffset = g_tableScrollOffset;
   g_tableScrollOffset += deltaRows;
   ClampTableScrollOffset();
   if(previousOffset != g_tableScrollOffset)
      RedrawTableNow();
  }

void ScrollTableToBoundary(bool toOldest)
  {
   int previousOffset = g_tableScrollOffset;
   if(toOldest)
      g_tableScrollOffset = GetTableScrollOffsetMax();
   else
      g_tableScrollOffset = 0;

   ClampTableScrollOffset();
   if(previousOffset != g_tableScrollOffset)
      RedrawTableNow();
  }

//+------------------------------------------------------------------+
//| Canonical direction mapping for trade actions                    |
//+------------------------------------------------------------------+
string ResolveTradeDirection(int ticketType, bool isCloseAction)
  {
   if(ticketType == OP_BUY)
      return(isCloseAction ? "SELL" : "BUY");

   if(ticketType == OP_SELL)
      return(isCloseAction ? "BUY" : "SELL");

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
   ResetTradeActionBaselineStorage();
  }

void ResetTradeActionBaselineStorage()
  {
   ArrayResize(g_tradeActionSymbolBaselines, 0);
   g_tradeActionSymbolBaselineCount = 0;
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
   action.exposure = 0.0;
   action.profit = GetOpenTicketFloatingProfit(snapshot.ticket);
   action.ticketDirection = ResolveTicketDirection(snapshot.ticketType);
   action.millisecondsSinceLastAction = 0;
   action.priceDifferenceFromPrevious = 0.0;
   action.hasPriceDifferenceFromPrevious = false;
   action.profitSinceStart = 0.0;
   action.actionTime = snapshot.openTime;
   action.actionTimeMs = snapshot.openTimeMs;
   SetMeasuredTimestampNow(action);
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
   action.exposure = 0.0;
   action.profit = realizedProfit;
   action.ticketDirection = ResolveTicketDirection(historyTicketType);
   action.millisecondsSinceLastAction = 0;
   action.priceDifferenceFromPrevious = 0.0;
   action.hasPriceDifferenceFromPrevious = false;
   action.profitSinceStart = 0.0;
   action.actionTime = closeTime;
   action.actionTimeMs = closeTimeMs;
   SetMeasuredTimestampNow(action);
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
   // 1) older broker actionTimeMs first
   // 2) for same timestamp: open before close
   // 3) then lower ticket first
   for(int i = 1; i < g_tradeActionCount; i++)
     {
      TradeActionRow key = g_tradeActions[i];
      int j = i - 1;

      while(j >= 0)
        {
         long currentSortTimeMs = GetTradeActionSortTimeMs(g_tradeActions[j]);
         long keySortTimeMs = GetTradeActionSortTimeMs(key);
         bool shouldShift = (currentSortTimeMs > keySortTimeMs);
         if(currentSortTimeMs == keySortTimeMs)
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

   TradeActionSymbolState newBaselines[];
   int newBaselineCount = 0;
   CopyTradeActionSymbolBaselines(newBaselines, newBaselineCount);
   if(g_tradeActionSymbolBaselineCount > 0 && newBaselineCount != g_tradeActionSymbolBaselineCount)
      return(false);

   for(int i = 0; i < dropCount; i++)
     {
      TradeActionRow dropped = g_tradeActions[i];
      int stateIndex = EnsureTradeActionSymbolState(newBaselines, newBaselineCount, dropped.symbolName);
      if(stateIndex < 0)
         return(false);

      UpdateTradeActionSymbolStateFromAction(newBaselines[stateIndex], dropped);
     }

   TradeActionRow retained[];
   if(ArrayResize(retained, maxActions) != maxActions)
      return(false);

   for(int i = 0; i < maxActions; i++)
      retained[i] = g_tradeActions[dropCount + i];

   if(ArrayResize(g_tradeActions, maxActions) != maxActions)
      return(false);

   for(int i = 0; i < maxActions; i++)
      g_tradeActions[i] = retained[i];

   if(ArrayResize(g_tradeActionSymbolBaselines, newBaselineCount) != newBaselineCount)
      return(false);

   for(int i = 0; i < newBaselineCount; i++)
      g_tradeActionSymbolBaselines[i] = newBaselines[i];

   g_tradeActionSymbolBaselineCount = newBaselineCount;
   g_tradeActionCount = maxActions;
   return(true);
  }

double GetSignedQuantity(string tradeDirection, double lots)
  {
   if(lots < 0.0)
      lots = -lots;

   if(tradeDirection == "BUY")
      return(lots);

   if(tradeDirection == "SELL")
      return(-lots);

   return(0.0);
  }

double RoundTradeActionValue(double value)
  {
   return(NormalizeDouble(value, TA_DERIVED_DECIMALS));
  }

bool IsOppositeTradeDirection(string currentDirection, string previousDirection)
  {
   if(currentDirection == "BUY" && previousDirection == "SELL")
      return(true);

   if(currentDirection == "SELL" && previousDirection == "BUY")
      return(true);

   return(false);
  }

int FindTradeActionSymbolStateIndex(TradeActionSymbolState &states[], int count, string symbolName)
  {
   for(int i = 0; i < count; i++)
     {
      if(states[i].symbolName == symbolName)
         return(i);
     }

   return(-1);
  }

int EnsureTradeActionSymbolState(TradeActionSymbolState &states[], int &count, string symbolName)
  {
   int existingIndex = FindTradeActionSymbolStateIndex(states, count, symbolName);
   if(existingIndex >= 0)
      return(existingIndex);

   int newSize = count + 1;
   if(ArrayResize(states, newSize) != newSize)
      return(-1);

   TradeActionSymbolState state;
   state.symbolName = symbolName;
   state.hasPreviousAction = false;
   state.tradeDirection = "";
   state.actionTimeMs = 0;
   state.executionPrice = 0.0;
   state.exposure = 0.0;
   state.profitSinceStart = 0.0;
   state.hasMeasuredTimestamp = false;
   state.measuredTimestampMs = 0;

   states[newSize - 1] = state;
   count = newSize;
   return(newSize - 1);
  }

void CopyTradeActionSymbolBaselines(TradeActionSymbolState &states[], int &count)
  {
   count = g_tradeActionSymbolBaselineCount;
   if(ArrayResize(states, count) != count)
     {
      count = 0;
      return;
     }

   for(int i = 0; i < count; i++)
      states[i] = g_tradeActionSymbolBaselines[i];
  }

void UpdateTradeActionSymbolStateFromAction(TradeActionSymbolState &state, const TradeActionRow &action)
  {
   state.symbolName = action.symbolName;
   state.hasPreviousAction = true;
   state.tradeDirection = action.tradeDirection;
   state.actionTimeMs = action.actionTimeMs;
   state.executionPrice = action.executionPrice;
   state.exposure = action.exposure;
   state.profitSinceStart = action.profitSinceStart;
   state.hasMeasuredTimestamp = action.hasMeasuredTimestamp;
   state.measuredTimestampMs = action.measuredTimestampMs;
  }

void RecalculateTradeActionDerivedFieldsCore()
  {
   if(g_tradeActionCount <= 0)
      return;

   TradeActionSymbolState states[];
   int stateCount = 0;
   CopyTradeActionSymbolBaselines(states, stateCount);
   if(g_tradeActionSymbolBaselineCount > 0 && stateCount != g_tradeActionSymbolBaselineCount)
      return;

   for(int i = 0; i < g_tradeActionCount; i++)
     {
      TradeActionRow action = g_tradeActions[i];
      int stateIndex = EnsureTradeActionSymbolState(states, stateCount, action.symbolName);
      if(stateIndex < 0)
         return;

      TradeActionSymbolState state = states[stateIndex];
      double previousExposure = state.hasPreviousAction ? state.exposure : 0.0;
      double previousProfit = state.hasPreviousAction ? state.profitSinceStart : 0.0;

      action.exposure = RoundTradeActionValue(previousExposure + GetSignedQuantity(action.tradeDirection, action.lots));

      action.millisecondsSinceLastAction = 0;
      if(state.hasPreviousAction &&
         state.hasMeasuredTimestamp &&
         action.hasMeasuredTimestamp &&
         action.measuredTimestampMs >= state.measuredTimestampMs)
         action.millisecondsSinceLastAction = action.measuredTimestampMs - state.measuredTimestampMs;

      action.hasPriceDifferenceFromPrevious = false;
      action.priceDifferenceFromPrevious = 0.0;
      action.profitSinceStart = RoundTradeActionValue(previousProfit);
      if(state.hasPreviousAction &&
         MathAbs(previousExposure) > TA_EXPOSURE_EPSILON &&
         IsOppositeTradeDirection(action.tradeDirection, state.tradeDirection))
        {
         double priceDifference = 0.0;
         if(action.tradeDirection == "BUY")
            priceDifference = state.executionPrice - action.executionPrice;
         else if(action.tradeDirection == "SELL")
            priceDifference = action.executionPrice - state.executionPrice;

         action.hasPriceDifferenceFromPrevious = true;
         action.priceDifferenceFromPrevious = RoundTradeActionValue(priceDifference);
         action.profitSinceStart = RoundTradeActionValue(previousProfit + action.priceDifferenceFromPrevious);
        }

      g_tradeActions[i] = action;
      UpdateTradeActionSymbolStateFromAction(state, action);
      states[stateIndex] = state;
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
      action.exposure = 0.0;
      action.profit = GetOpenTicketFloatingProfit(snapshot.ticket);
      action.ticketDirection = ResolveTicketDirection(snapshot.ticketType);
      action.millisecondsSinceLastAction = 0;
      action.priceDifferenceFromPrevious = 0.0;
      action.hasPriceDifferenceFromPrevious = false;
      action.profitSinceStart = 0.0;
      action.actionTime = snapshot.openTime;
      action.actionTimeMs = snapshot.openTimeMs;
      ClearMeasuredTimestamp(action);
      action.ticketType = snapshot.ticketType;

      AppendTradeAction(action);
      seededCount++;
     }

   if(seededCount > 0)
      PrintFormat("TradeAction: Seeded %d baseline open actions.", seededCount);

   RecalculateTradeActionDerivedFields();
  }

string FormatMeasuredTimestamp(const TradeActionRow &action)
  {
   if(!action.hasMeasuredTimestamp)
      return(TA_VALUE_NOT_AVAILABLE);

   int millisecondsPart = (int)(action.measuredTimestampMs % 1000);
   return(StringFormat("%s.%03d",
                       TimeToString(action.measuredTimestampLocal, TIME_DATE | TIME_SECONDS),
                       millisecondsPart));
  }

string FormatPriceDifferenceFromPrevious(const TradeActionRow &action)
  {
   if(!action.hasPriceDifferenceFromPrevious)
      return(TA_VALUE_NOT_AVAILABLE);

   return(DoubleToString(action.priceDifferenceFromPrevious, Digits));
  }

string FormatProfitSinceStart(const TradeActionRow &action)
  {
   return(DoubleToString(action.profitSinceStart, Digits));
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

void CreateTableButton(string name, string text, int x, int y, int width, int height, bool enabled)
  {
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
      return;

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_COLOR, enabled ? InpTextColor : InpEmptyTextColor);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, enabled ? InpHeaderBackgroundColor : InpPanelBackgroundColor);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
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
      case 7: return(COL_W_MEASURED_TIMESTAMP);
      case 8: return(COL_W_MILLISECONDS_SINCE_LAST);
      case 9: return(COL_W_PRICE_DIFF_FROM_PREVIOUS);
      case 10: return(COL_W_PROFIT_SINCE_START);
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
      case 1: return("Symbol");
      case 2: return("OpenOrClose");
      case 3: return("TradeDirection");
      case 4: return("TicketDirection");
      case 5: return("ExecutionPrice");
      case 6: return("Exposure");
      case 7: return("MeasuredTimestamp");
      case 8: return("Ms_LastAction");
      case 9: return("Pricediff");
      case 10: return("ProfitSinceStart");
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
                    string measuredTimestamp,
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
      case 7: return(measuredTimestamp);
      case 8: return(millisecondsSinceLastAction);
      case 9: return(priceDifferenceFromPrevious);
      case 10: return(profitSinceStart);
     }
   return("");
  }
//+------------------------------------------------------------------+
