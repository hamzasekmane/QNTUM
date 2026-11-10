//+------------------------------------------------------------------+
//|  Regression: audit of previously recorded decisions                 |
//+------------------------------------------------------------------+
#property strict
#include "Test_PreviousSignals.mqh"
int OnInit(void) { return(RunPreviousSignalTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
