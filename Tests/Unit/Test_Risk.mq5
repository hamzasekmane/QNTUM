//+------------------------------------------------------------------+
//|  Unit: risk sizing and daily guard                                 |
//+------------------------------------------------------------------+
#property strict
#include "Test_Risk.mqh"
int OnInit(void) { return(RunRiskTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
