//+------------------------------------------------------------------+
//|  Validation: full state round trip (restart recovery)               |
//+------------------------------------------------------------------+
#property strict
#include "Test_RestartRecovery.mqh"
int OnInit(void) { return(RunRestartRecoveryTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
