//+------------------------------------------------------------------+
//|  Validation: DEMO authorization matrix                             |
//+------------------------------------------------------------------+
#property strict
#include "Test_DemoTrading.mqh"
int OnInit(void) { return(RunDemoTradingTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
