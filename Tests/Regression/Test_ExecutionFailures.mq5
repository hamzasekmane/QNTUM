//+------------------------------------------------------------------+
//|  Regression: execution failure policy                              |
//+------------------------------------------------------------------+
#property strict
#include "Test_ExecutionFailures.mqh"
int OnInit(void) { return(RunExecutionFailureTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
