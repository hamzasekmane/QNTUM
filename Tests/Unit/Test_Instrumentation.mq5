//+------------------------------------------------------------------+
//|  Unit: instrumentation (funnel, profiler, events)                  |
//+------------------------------------------------------------------+
#property strict
#include "Test_Instrumentation.mqh"
int OnInit(void) { return(RunInstrumentationTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
