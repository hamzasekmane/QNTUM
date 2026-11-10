//+------------------------------------------------------------------+
//|  Unit: canonical snapshot                                          |
//+------------------------------------------------------------------+
#property strict
#include "Test_Canonical.mqh"
int OnInit(void) { return(RunCanonicalTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
