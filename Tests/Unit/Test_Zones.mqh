//+------------------------------------------------------------------+
//|                                        Tests/Unit/Test_Zones      |
//|  Zone identity, validation, merging and ranking.                     |
//|  Pure logic: no market data required.                              |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_ZONES_MQH__
#define __QME_TEST_ZONES_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

void MakeZone(STradingZone &z, const ENUM_QME_SIDE side, const double lower, const double upper,
              const double strength, const datetime now)
  {
   z.id = CZoneIdentity::Make("EURUSD", PERIOD_M15, side, QME_ZONE_SRC_ORDER_BLOCK,
                              lower, upper, 0.00001);
   z.symbol = "EURUSD";
   z.tf = PERIOD_M15;
   z.side = side;
   z.source = QME_ZONE_SRC_ORDER_BLOCK;
   z.lower = lower;
   z.upper = upper;
   z.created = now - 3600;
   z.lastTouched = now - 600;
   z.expires = now + 86400;
   z.touches = 1;
   z.strength = strength;
   z.confidence = 0.7;
   z.state = QME_ZSTAT_FRESH;
   z.invalidateLevel = (side == QME_SIDE_BUY) ? lower - 0.0010 : upper + 0.0010;
   z.factorMask = CFactorCatalog::Bit(QME_F_ORDER_BLOCK);
   z.merged = false;
   z.parentId = 0;
  }

int RunZoneTests(void)
  {
   g_kit.Begin("Unit/Test_Zones");
   const datetime now = TimeCurrent();

   //--- identity determinism
   const ulong a = CZoneIdentity::Make("EURUSD", PERIOD_M15, QME_SIDE_BUY,
                                       QME_ZONE_SRC_ORDER_BLOCK, 1.1000, 1.1020, 0.00001);
   const ulong b = CZoneIdentity::Make("EURUSD", PERIOD_M15, QME_SIDE_BUY,
                                       QME_ZONE_SRC_ORDER_BLOCK, 1.1000, 1.1020, 0.00001);
   const ulong c = CZoneIdentity::Make("EURUSD", PERIOD_M15, QME_SIDE_SELL,
                                       QME_ZONE_SRC_ORDER_BLOCK, 1.1000, 1.1020, 0.00001);
   g_kit.Check(a == b, "identity is deterministic");
   g_kit.Check(a != c, "identity distinguishes side");
   g_kit.Check(a != 0, "identity is non-zero");

   //--- validation
   STradingZone bad;
   MakeZone(bad, QME_SIDE_BUY, 1.1020, 1.1000, 0.8, now);   // upper < lower
   string why = "";
   g_kit.Check(!CZoneValidator::IsValid(bad, 0.00001, now, why), "inverted zone rejected");
   g_kit.Check(StringLen(why) > 0, "rejection explains itself");

   STradingZone good;
   MakeZone(good, QME_SIDE_BUY, 1.1000, 1.1020, 0.8, now);
   g_kit.Check(CZoneValidator::IsValid(good, 0.00001, now, why), "valid zone accepted");

   STradingZone expiredZone = good;
   expiredZone.expires = now - 60;
   g_kit.Check(CZoneValidator::IsExpired(expiredZone, now), "expired zone detected");

   //--- board merge: identical side + overlap must merge
   CZoneBoard board;
   board.Init("EURUSD");
   STradingZone z1, z2;
   MakeZone(z1, QME_SIDE_BUY, 1.1000, 1.1020, 0.6, now);
   MakeZone(z2, QME_SIDE_BUY, 1.1010, 1.1030, 0.9, now);
   board.AddOrMerge(z1, 60.0);
   //--- z1/z2 share 0.0010 of their 0.0020 height = 50% of the smaller
   //--- zone, which is the documented merge metric: at a 40% threshold
   //--- they must merge; a 60% threshold must refuse them (see below)
   board.AddOrMerge(z2, 40.0);
   g_kit.CheckEqual(board.Count(), 1, "overlapping same-side zones merge");
   g_kit.Check(board.MergedCount() >= 1, "merge counter incremented");

   //--- opposite side never merges
   STradingZone z3;
   MakeZone(z3, QME_SIDE_SELL, 1.1000, 1.1020, 0.5, now);
   board.AddOrMerge(z3, 40.0);
   g_kit.CheckEqual(board.Count(), 2, "opposite-side zone is kept separate");

   //--- the tolerance gate is real: same geometry at a 60% threshold
   CZoneBoard strict;
   strict.Init("EURUSD");
   STradingZone s1, s2;
   MakeZone(s1, QME_SIDE_BUY, 1.1000, 1.1020, 0.6, now);
   MakeZone(s2, QME_SIDE_BUY, 1.1010, 1.1030, 0.9, now);
   strict.AddOrMerge(s1, 60.0);
   strict.AddOrMerge(s2, 60.0);
   g_kit.CheckEqual(strict.Count(), 2, "50% overlap stays separate at a 60% threshold");
   g_kit.CheckEqual(strict.MergedCount(), 0, "no merge counted below the threshold");

   //--- containment merges and keeps the outer boundary
   CZoneBoard cont;
   cont.Init("EURUSD");
   STradingZone outer, inner;
   MakeZone(outer, QME_SIDE_BUY, 1.1000, 1.1040, 0.6, now);
   MakeZone(inner, QME_SIDE_BUY, 1.1010, 1.1020, 0.9, now);
   cont.AddOrMerge(outer, 60.0);
   cont.AddOrMerge(inner, 60.0);
   g_kit.CheckEqual(cont.Count(), 1, "a contained zone merges into its container");
   STradingZone mergedZone;
   g_kit.Check(cont.At(0, mergedZone) && mergedZone.lower == 1.1000 && mergedZone.upper == 1.1040,
               "merged boundary is deterministic (the outer envelope)");

   //--- re-adding the identical zone refreshes it instead of duplicating
   CZoneBoard dupe;
   dupe.Init("EURUSD");
   STradingZone d1;
   MakeZone(d1, QME_SIDE_BUY, 1.1000, 1.1020, 0.6, now);
   dupe.AddOrMerge(d1, 60.0);
   dupe.AddOrMerge(d1, 60.0);
   g_kit.CheckEqual(dupe.Count(), 1, "repeated insertion of the same zone does not duplicate");

   //--- ranking prefers strength
   STradingZone weak, strong;
   MakeZone(weak, QME_SIDE_BUY, 1.1000, 1.1010, 0.2, now);
   MakeZone(strong, QME_SIDE_BUY, 1.1000, 1.1010, 1.0, now);
   const double sw = CZoneRanking::Score(weak, 1.1005, 0.0010, now);
   const double ss = CZoneRanking::Score(strong, 1.1005, 0.0010, now);
   g_kit.Check(ss > sw, "stronger zone ranks higher");
   g_kit.Check(ss <= 1.0 && ss >= 0.0, "ranking score stays in [0,1]");

   return(g_kit.End());
  }

#endif // __QME_TEST_ZONES_MQH__
//+------------------------------------------------------------------+
