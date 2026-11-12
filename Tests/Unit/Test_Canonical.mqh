//+------------------------------------------------------------------+
//|                                      Tests/Unit/Test_Canonical    |
//|  Runtime/CanonicalSnapshot: determinism, serialisation, equivalence.  |
//|  No market data and no engine: every snapshot is fabricated.          |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_CANONICAL_MQH__
#define __QME_TEST_CANONICAL_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

//--- explicit copy: no struct assignment on a type that holds strings
void QmeTestCopySnap(const SCanonicalSnapshot &src, SCanonicalSnapshot &dst)
  {
   dst.cycle      = src.cycle;
   dst.time       = src.time;
   dst.symbol     = src.symbol;
   dst.tf         = src.tf;
   dst.price      = src.price;
   dst.atr        = src.atr;
   dst.bias       = src.bias;
   dst.biasScore  = src.biasScore;
   dst.zoneCount  = src.zoneCount;
   dst.candidates = src.candidates;
   dst.signals    = src.signals;
   dst.approved   = src.approved;
   dst.session    = src.session;
   dst.digest     = src.digest;
  }

void QmeTestMakeSnap(SCanonicalSnapshot &s)
  {
   QmeCanonicalClear(s);
   s.cycle      = 7;
   s.time       = D'2024.01.02 10:00';
   s.symbol     = "EURUSD";
   s.tf         = PERIOD_H1;
   s.price      = 1.10500;
   s.atr        = 0.00120;
   s.bias       = QME_SIDE_BUY;
   s.biasScore  = 0.720;
   s.zoneCount  = 6;
   s.candidates = 2;
   s.signals    = 1;
   s.approved   = 1;
   s.session    = QME_SESSION_LONDON;
  }

int RunCanonicalTests(void)
  {
   g_kit.Begin("Unit/Test_Canonical");

   const string scopeA=QmeScopedStateName(52959880,"ICMarketsSC-Demo",20261110);
   g_kit.CheckStr(scopeA,QmeScopedStateName(52959880,"ICMarketsSC-Demo",20261110),
                  "state scope name is deterministic");
   g_kit.Check(scopeA!=QmeScopedStateName(52959881,"ICMarketsSC-Demo",20261110),
               "account login isolates persisted state");
   g_kit.Check(scopeA!=QmeScopedStateName(52959880,"Other-Demo",20261110),
               "broker server isolates persisted state");
   g_kit.Check(scopeA!=QmeScopedStateName(52959880,"ICMarketsSC-Demo",20261111),
               "EA magic isolates persisted state");

   //--- timeframes survive the name round trip
   g_kit.Check(QmeTfFromName(QmeTfName(PERIOD_M5))  == PERIOD_M5,  "M5 name round trip");
   g_kit.Check(QmeTfFromName(QmeTfName(PERIOD_H1))  == PERIOD_H1,  "H1 name round trip");
   g_kit.Check(QmeTfFromName(QmeTfName(PERIOD_D1))  == PERIOD_D1,  "D1 name round trip");
   g_kit.Check(QmeTfFromName("nonsense") == PERIOD_CURRENT, "unknown name maps to PERIOD_CURRENT");

   SCanonicalSnapshot a;
   QmeTestMakeSnap(a);

   //--- determinism: same state, same digest, every time
   const string d1 = CCanonicalSnapshot::Digest(a);
   const string d2 = CCanonicalSnapshot::Digest(a);
   g_kit.CheckStr(d1, d2, "digest is deterministic");
   g_kit.CheckEqual(StringLen(d1), 16, "digest is 16 hex characters");
   string upper = d1;
   StringToUpper(upper);
   g_kit.Check(d1 == upper, "digest is upper-case hex");

   //--- bookkeeping fields are not part of the state fingerprint
   SCanonicalSnapshot later;
   QmeTestCopySnap(a, later);
   later.cycle = 99;
   later.time  = D'2024.01.03 11:30';
   g_kit.CheckStr(CCanonicalSnapshot::Digest(later), d1,
                  "cycle and timestamp do not change the digest");

   //--- a different market state must change it
   SCanonicalSnapshot moved;
   QmeTestCopySnap(a, moved);
   moved.price = a.price + 0.00001;
   g_kit.Check(CCanonicalSnapshot::Digest(moved) != d1, "a one-point price move changes the digest");

   SCanonicalSnapshot zoned;
   QmeTestCopySnap(a, zoned);
   zoned.zoneCount = a.zoneCount + 1;
   g_kit.Check(CCanonicalSnapshot::Digest(zoned) != d1, "zone count is part of the digest");

   SCanonicalSnapshot flipped;
   QmeTestCopySnap(a, flipped);
   flipped.bias = QME_SIDE_SELL;
   g_kit.Check(CCanonicalSnapshot::Digest(flipped) != d1, "bias is part of the digest");

   //--- serialisation round trip
   a.digest = d1;
   const string line = CCanonicalSnapshot::Serialize(a);
   g_kit.Check(StringLen(line) > 0, "serialize returns a line");

   SCanonicalSnapshot back;
   QmeCanonicalClear(back);
   g_kit.Check(CCanonicalSnapshot::Deserialize(line, back), "serialize/deserialize round trip succeeds");
   g_kit.CheckStr(back.symbol, a.symbol, "round trip keeps the symbol");
   g_kit.Check(back.tf == a.tf, "round trip keeps the timeframe");
   g_kit.Check(back.bias == a.bias, "round trip keeps the bias");
   g_kit.CheckEqual(back.zoneCount, a.zoneCount, "round trip keeps the zone count");
   g_kit.CheckClose(back.price, a.price, 1e-8, "round trip keeps the price");
   g_kit.CheckClose(back.atr, a.atr, 1e-8, "round trip keeps the ATR");
   g_kit.CheckStr(back.digest, d1, "round trip keeps the digest");
   g_kit.CheckStr(CCanonicalSnapshot::Digest(back), d1, "the restored state hashes to the same digest");

   //--- malformed input is refused, never half-applied
   SCanonicalSnapshot junk;
   g_kit.Check(!CCanonicalSnapshot::Deserialize("snap|1|2", junk), "short line is rejected");
   g_kit.Check(!CCanonicalSnapshot::Deserialize("", junk), "empty line is rejected");
   g_kit.Check(!CCanonicalSnapshot::Deserialize("other|1|2|EURUSD|H1|1|1|BUY|0.5|1|1|1|1|3|X", junk),
                "wrong tag is rejected");

   //--- equivalence
   g_kit.Check(CCanonicalSnapshot::Equivalent(a, back), "round-tripped snapshot is equivalent");
   g_kit.Check(!CCanonicalSnapshot::Equivalent(a, zoned), "different zone count is not equivalent");

   SCanonicalSnapshot near;
   QmeTestCopySnap(a, near);
   near.price = a.price + 0.00005;
   near.digest = CCanonicalSnapshot::Digest(near);
   g_kit.Check(!CCanonicalSnapshot::Equivalent(a, near),
               "with no tolerance any price difference is a mismatch");
   g_kit.Check(CCanonicalSnapshot::Equivalent(a, near, 0.0001),
               "with tolerance the small move is equivalent");

   return(g_kit.End());
  }

#endif // __QME_TEST_CANONICAL_MQH__
