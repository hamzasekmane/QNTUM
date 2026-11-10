//+------------------------------------------------------------------+
//|  Unit: signal lifecycle state machine                              |
//+------------------------------------------------------------------+
#property strict
#include "Test_SignalLifecycle.mqh"
int OnInit(void) { return(RunLifecycleTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
