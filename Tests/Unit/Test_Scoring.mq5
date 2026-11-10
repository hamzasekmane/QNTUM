//+------------------------------------------------------------------+
//|  Unit: scoring engine                                              |
//+------------------------------------------------------------------+
#property strict
#include "Test_Scoring.mqh"
int OnInit(void) { return(RunScoringTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
