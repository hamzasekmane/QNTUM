//+------------------------------------------------------------------+
//|  Integration: candidate collection and clustering                  |
//+------------------------------------------------------------------+
#property strict
#include "Test_MtfPipeline.mqh"
int OnInit(void) { return(RunMtfPipelineTest()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
