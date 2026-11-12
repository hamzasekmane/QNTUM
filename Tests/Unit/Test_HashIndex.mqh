//+------------------------------------------------------------------+
//| Unit: bounded fingerprint index collision/deletion/rebuild tests  |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_HASHINDEX_MQH__
#define __QME_TEST_HASHINDEX_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_hashKit;

int RunHashIndexTests(void)
  {
   g_hashKit.Begin("Unit/Test_HashIndex");
   CSignalDeduplicator dedup;
   dedup.Reset();
   g_hashKit.Check(!dedup.IsDuplicate("", 30, 100), "empty key is not duplicate");
   g_hashKit.Check(!dedup.Register("", 1, 100), "empty key is rejected");
   g_hashKit.Check(!dedup.IsDuplicate("absent", 30, 100), "empty table miss");

   //--- force a collision in the index's initial bucket; full strings must disambiguate
   string first = "", second = "";
   string seen[1024];
   for(int i = 0; i < 5000 && StringLen(second) == 0; i++)
     {
      const string key = "collision-" + IntegerToString(i);
      const int b = (int)(QmeHashString(key) % 1024);
      if(StringLen(seen[b]) > 0) { first = seen[b]; second = key; }
      else seen[b] = key;
     }
   g_hashKit.Check(StringLen(first) > 0 && StringLen(second) > 0,
                   "fixture finds two distinct keys with same initial bucket");
   g_hashKit.Check(dedup.Register(first, 101, 100), "insert first colliding key");
   g_hashKit.Check(dedup.Register(second, 102, 101), "insert second colliding key");
   g_hashKit.Check(dedup.IsDuplicate(first, 30, 110), "collision probe finds first key");
   g_hashKit.Check(dedup.IsDuplicate(second, 30, 110), "collision probe finds second key");
   g_hashKit.Check(dedup.Register(first, 103, 111), "re-register updates existing key");
   g_hashKit.Check(dedup.IsDuplicate(first, 30, 112), "updated key remains indexed");
   g_hashKit.Check(!dedup.IsDuplicate("different", 30, 110), "collision does not create false membership");
   g_hashKit.Check(!dedup.IsDuplicate(first, 30, 141), "cooldown boundary expires exactly at threshold");

   //--- pruning removes indexed entries and leaves colliding survivors searchable
   dedup.Prune(20, 150);
   g_hashKit.CheckEqual(dedup.Count(), 0, "expired records pruned");
   g_hashKit.Check(!dedup.IsDuplicate(first, 30, 150), "pruned key no longer found");
   g_hashKit.Check(dedup.Register("after-prune", 203, 151), "insert after index rebuild");
   g_hashKit.Check(dedup.IsDuplicate("after-prune", 30, 152), "post-prune index remains usable");

   //--- serialization/rebuild restores the secondary index from authoritative records
   dedup.Register(first, 201, 200);
   dedup.Register(second, 202, 201);
   const string blob = dedup.Serialize();
   CSignalDeduplicator restored;
   g_hashKit.Check(restored.Deserialize(blob), "valid records deserialize");
   g_hashKit.Check(restored.IsDuplicate(first, 30, 205), "first key indexed after restore");
   g_hashKit.Check(restored.IsDuplicate(second, 30, 205), "second colliding key indexed after restore");

   //--- bounded ring eviction removes stale mapping and admits new key
   CSignalDeduplicator full;
   bool filled = true;
   for(int i = 0; i < QME_MAX_FINGERPRINTS; i++)
      if(!full.Register("capacity-" + IntegerToString(i), (ulong)(i + 1), 1000 + i))
        { filled = false; break; }
   g_hashKit.Check(filled, "all records insert through configured capacity");
   g_hashKit.CheckEqual(full.Count(), QME_MAX_FINGERPRINTS, "index remains bounded at capacity");
   g_hashKit.Check(full.Register("capacity-new", 9000, 2000), "ring accepts item by evicting oldest");
   g_hashKit.Check(!full.IsDuplicate("capacity-0", 30, 2001), "evicted fingerprint removed from index");
   g_hashKit.Check(full.IsDuplicate("capacity-new", 30, 2001), "new ring key indexed");
   g_hashKit.CheckEqual(full.Count(), QME_MAX_FINGERPRINTS, "ring count stays at capacity");

   return(g_hashKit.End());
  }

#endif // __QME_TEST_HASHINDEX_MQH__
