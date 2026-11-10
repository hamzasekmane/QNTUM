//+------------------------------------------------------------------+
//|  Integration: market data -> scanner -> analysis                   |
//+------------------------------------------------------------------+
#property strict
#include "Test_MarketPipeline.mqh"
int OnInit(void) { return(RunMarketPipelineTest()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
