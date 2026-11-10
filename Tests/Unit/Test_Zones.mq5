//+------------------------------------------------------------------+
//|                                    QuantumMarketEngine test       |
//|  Unit: zones (identity, validation, merge, ranking)               |
//|  Run: Strategy Tester -> any symbol -> this EA, or on a chart.    |
//+------------------------------------------------------------------+
#property strict

#include "Test_Zones.mqh"

int OnInit(void) { return(RunZoneTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
