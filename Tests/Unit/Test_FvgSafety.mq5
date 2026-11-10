//+------------------------------------------------------------------+
//|  Unit: FVG / order-block buffer safety                             |
//+------------------------------------------------------------------+
#property strict
#include "Test_FvgSafety.mqh"
int OnInit(void) { return(RunFvgSafetyTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
