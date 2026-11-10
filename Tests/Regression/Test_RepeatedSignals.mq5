//+------------------------------------------------------------------+
//|  Regression: repeated signal suppression                           |
//+------------------------------------------------------------------+
#property strict
#include "Test_RepeatedSignals.mqh"
int OnInit(void) { return(RunRepeatedSignalTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
