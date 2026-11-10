//+------------------------------------------------------------------+
//|  Integration: execution pipeline (no order is ever sent)            |
//+------------------------------------------------------------------+
#property strict
#include "Test_Execution.mqh"
int OnInit(void) { return(RunExecutionTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
