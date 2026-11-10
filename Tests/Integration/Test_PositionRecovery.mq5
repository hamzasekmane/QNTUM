//+------------------------------------------------------------------+
//|  Integration: position tracking + restart reconciliation            |
//+------------------------------------------------------------------+
#property strict
#include "Test_PositionRecovery.mqh"
int OnInit(void) { return(RunPositionRecoveryTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
