//+------------------------------------------------------------------+
//| Unit: signal fingerprint hash index                               |
//+------------------------------------------------------------------+
#property strict
#include "Test_HashIndex.mqh"
int OnInit(void) { return(RunHashIndexTests()); }
void OnTick(void) {}
void OnDeinit(const int reason) {}
