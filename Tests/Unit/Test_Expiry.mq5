//+------------------------------------------------------------------+
//|  Unit: signal expiry                                               |
//+------------------------------------------------------------------+
#property strict
#include "Test_Expiry.mqh"
int OnInit(void) { return(RunExpiryTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
