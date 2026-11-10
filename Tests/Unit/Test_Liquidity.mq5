//+------------------------------------------------------------------+
//|  Unit: liquidity map lookups                                       |
//+------------------------------------------------------------------+
#property strict
#include "Test_Liquidity.mqh"
int OnInit(void) { return(RunLiquidityTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
