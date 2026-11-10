//+------------------------------------------------------------------+
//|  Validation: REAL account authorization matrix                     |
//|  Run this before any REAL deployment.                              |
//+------------------------------------------------------------------+
#property strict
#include "Test_RealAccountSafety.mqh"
int OnInit(void) { return(RunRealAccountSafetyTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
