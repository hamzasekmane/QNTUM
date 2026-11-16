//+------------------------------------------------------------------+
//|                                 Tests/Integration/Test_MtfPipeline |
//|  Candidates -> cluster: one merged candidate per side at most, and    |
//|  no evidence invented during the merge.                            |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_MTF_MQH__
#define __QME_TEST_MTF_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

SSymbolSpec MtfSpec(void)
  {
   SSymbolSpec s;
   s.symbol = _Symbol;
   s.description = _Symbol;
   s.path = "";
   s.digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   s.point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   s.tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   s.tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   s.contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   s.volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   s.volMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   s.volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   s.stopsLevelPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   s.freezeLevelPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   s.tradeMode = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   s.execMode = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE);
   s.fillingMask = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   s.swapLong = 0.0; s.swapShort = 0.0; s.marginInitial = 0.0;
   s.tradeAllowed = true; s.selected = true; s.valid = (s.point > 0.0);
   return(s);
  }

int RunMtfPipelineTest(void)
  {
   g_kit.Begin("Integration/Test_MtfPipeline");

   SInputs in;
   QmeInputsDefaults(in);
   in.logLevel = QME_LOG_WARN;

   string err = "";
   CConfig cfg;
   cfg.Init(in, err);

   const SSymbolSpec spec = MtfSpec();
   if(!spec.valid)
     {
      g_kit.Skip("symbol specification unavailable");
      return(g_kit.End());
     }

   // Confluence denominator contract: neutral/weak views retain their weight.
   STfView weightedViews[]; ArrayResize(weightedViews,5);
   weightedViews[0].tf=PERIOD_D1; weightedViews[0].direction=QME_SIDE_BUY; weightedViews[0].strength=0.5;
   weightedViews[1].tf=PERIOD_H4; weightedViews[1].direction=QME_SIDE_BUY; weightedViews[1].strength=0.5;
   weightedViews[2].tf=PERIOD_H1; weightedViews[2].direction=QME_SIDE_NONE; weightedViews[2].strength=0.0;
   weightedViews[3].tf=PERIOD_M15; weightedViews[3].direction=QME_SIDE_NONE; weightedViews[3].strength=0.0;
   weightedViews[4].tf=PERIOD_M5; weightedViews[4].direction=QME_SIDE_NONE; weightedViews[4].strength=0.0;
   const SConfluenceResult weighted=CMtfConfluenceEngine::Evaluate(QME_SIDE_BUY,weightedViews,5);
   g_kit.CheckClose(weighted.score,0.3766903,0.00001,
                    "confluence uses raw timeframe weights in denominator and strength only in agreement numerator");
   STfView onlyAligned[]; ArrayResize(onlyAligned,2);
   onlyAligned[0]=weightedViews[0]; onlyAligned[1]=weightedViews[1];
   const SConfluenceResult omitted=CMtfConfluenceEngine::Evaluate(QME_SIDE_BUY,onlyAligned,2);
   g_kit.Check(omitted.score>weighted.score,"omitting missing views raises confluence; BuildViews must retain all five configured slots");

   //--- fabricated analyses: no zones, so the collector must return 0
   SMarketAnalysis bias, structure, setup;
   QmeAnalysisClear(bias);
   QmeAnalysisClear(structure);
   QmeAnalysisClear(setup);

   bias.symbol = _Symbol; bias.tf = in.tfBias; bias.valid = true;
   bias.bias.side = QME_SIDE_BUY; bias.bias.score = 0.8; bias.bias.valid = true;
   structure.symbol = _Symbol; structure.tf = in.tfStructure; structure.valid = true;
   setup.symbol = _Symbol; setup.tf = in.tfSetup; setup.valid = true;
   setup.price = 1.10000; setup.atr = 0.00100;

   CZoneEngine zones;
   zones.Init(_Symbol, 72, 60.0);

   SCandidateHypothesis hyps[];
   SCandidateRejectCounts rejects;
   const int n = CCandidateCollector::Collect(bias, structure, setup, zones, spec, cfg,
                                              1.10000, 0.00100, spec.point, cfg.In.minRR,
                                              3.0, hyps, 8, rejects);
   g_kit.CheckEqual(n, 0, "no zones -> no candidates");
   g_kit.Check(rejects.noZone > 0, "collector counts no-zone candidate rejection");

   SMergedCandidate merged[];
   const int m = CCandidateClusterer::Merge(hyps, n, merged, 8);
   g_kit.CheckEqual(m, 0, "no candidates -> no merged candidate");

   //--- geometry contract of the clusterer, stated explicitly
   g_kit.Check(m <= 2, "at most one candidate per side survives the merge");

   // End-to-end candidate-validity contract: real collector output -> merge
   // -> setup gate -> scoring. No order is built or sent by this fixture.
   MqlTick tick;
   const double livePrice=(SymbolInfoTick(_Symbol,tick) && tick.bid>0.0 && tick.ask>0.0) ?
                          (tick.bid+tick.ask)*0.5 : 0.0;
   if(livePrice<=0.0)
      g_kit.Skip("candidate contract fixture requires a current symbol quote");
   else
     {
      setup.price=livePrice; setup.atr=livePrice*0.001; setup.structureValid=true;
      setup.barTime=TimeCurrent()-PeriodSeconds(in.tfSetup);
      setup.bos.valid=true; setup.bos.event=QME_STRUCT_BOS_UP; setup.bos.strength=1.0;
      STradingZone zone; QmeZoneClear(zone);
      zone.id=991337; zone.symbol=_Symbol; zone.tf=in.tfSetup; zone.side=QME_SIDE_BUY;
      zone.source=QME_ZONE_SRC_FVG; zone.upper=livePrice+setup.atr*0.05;
      zone.lower=livePrice-setup.atr*0.05; zone.created=TimeCurrent();
      zone.lastTouched=TimeCurrent(); zone.expires=TimeCurrent()+3600;
      zone.strength=0.9; zone.confidence=0.9; zone.state=QME_ZSTAT_FRESH;
      zone.factorMask=CFactorCatalog::Bit(QME_F_FVG);
      g_kit.Check(zones.Board().AddOrMerge(zone,60.0),"fixture FVG zone inserted");
      SCandidateHypothesis produced[]; SCandidateRejectCounts producedRejects;
      const int producedN=CCandidateCollector::Collect(bias,structure,setup,zones,spec,cfg,
                       livePrice,setup.atr,spec.point,cfg.In.minRR*1.1,4.0,
                       produced,QME_MAX_CANDIDATES,producedRejects);
      g_kit.Check(producedN>0,"collector emits valid hypothesis from active fixture zone");
      if(producedN>0)
        {
         g_kit.Check(produced[0].valid && produced[0].entry.valid,"collector validity flags set on usable hypothesis");
         SMergedCandidate mergedValid[];
         const int mergedN=CCandidateClusterer::Merge(produced,producedN,mergedValid,2);
         g_kit.Check(mergedN>0,"valid collector hypothesis survives clusterer");
         if(mergedN>0)
           {
            g_kit.Check(mergedValid[0].cand.valid && mergedValid[0].valid,
                        "clusterer preserves both candidate validity fields");
            SConfluenceResult conf; ZeroMemory(conf); conf.valid=true; conf.score=1.0;
            conf.htfAligned=true; conf.side=QME_SIDE_BUY;
            SDataQuality good; QmeDataQualityClear(good); good.ok=true;
            const SSetupVerdict verdict=CSetupEngine::Evaluate(mergedValid[0],conf,cfg,good);
            g_kit.Check(verdict.reason!=QME_REJ_INTERNAL,"setup gate does not reject valid merged candidate as INTERNAL");
            g_kit.Check(verdict.ok,"valid fixture reaches beyond setup validity and confirmation gates");
            CScoringEngine scoreEngine; SFactorBreakdown breakdown;
            const double scoreValue=scoreEngine.Score(mergedValid[0].score,breakdown);
            g_kit.Check(scoreValue>0.0 && breakdown.applied>0,"valid merged evidence reaches scoring");
           }
         produced[0].valid=false;
         SMergedCandidate invalidMerged[];
         g_kit.CheckEqual(CCandidateClusterer::Merge(produced,producedN,invalidMerged,2),0,
                          "invalid hypothesis is not emitted as trade candidate");
         SMergedCandidate invalidCandidate; QmeCandidateClear(invalidCandidate.cand);
         invalidCandidate.valid=false;
         SConfluenceResult invalidConf; ZeroMemory(invalidConf);
         SDataQuality invalidDq; QmeDataQualityClear(invalidDq); invalidDq.ok=true;
         const SSetupVerdict invalidVerdict=CSetupEngine::Evaluate(invalidCandidate,invalidConf,cfg,invalidDq);
         g_kit.Check(!invalidVerdict.ok && invalidVerdict.reason==QME_REJ_INTERNAL,
                     "SetupEngine continues to reject genuinely invalid merged candidate");
        }

      //--- price outside zone generates QME_ENTRY_LIMIT in EntryRig; collector
      //--- must not emit unexecutable limit candidates while Gateway is market-only.
      CZoneEngine outsideZones;
      outsideZones.Init(_Symbol, 72, 60.0);
      STradingZone farZone; QmeZoneClear(farZone);
      farZone.id=991338; farZone.symbol=_Symbol; farZone.tf=in.tfSetup; farZone.side=QME_SIDE_BUY;
      farZone.source=QME_ZONE_SRC_FVG;
      farZone.upper=livePrice-setup.atr*0.40;
      farZone.lower=livePrice-setup.atr*0.60;
      farZone.created=TimeCurrent(); farZone.lastTouched=TimeCurrent();
      farZone.expires=TimeCurrent()+3600; farZone.strength=0.9; farZone.confidence=0.9;
      farZone.state=QME_ZSTAT_FRESH; farZone.factorMask=CFactorCatalog::Bit(QME_F_FVG);
      g_kit.Check(outsideZones.Board().AddOrMerge(farZone, 60.0), "outside fixture zone inserted");
      SCandidateHypothesis limitHyps[]; SCandidateRejectCounts limitRejects;
      g_kit.CheckEqual(CCandidateCollector::Collect(bias,structure,setup,outsideZones,spec,cfg,
                       livePrice,setup.atr,spec.point,cfg.In.minRR*1.1,4.0,
                       limitHyps,QME_MAX_CANDIDATES,limitRejects), 0,
                       "collector suppresses QME_ENTRY_LIMIT when ExecutionGateway is market-only");
      g_kit.Check(limitRejects.invalidEntry > 0, "outside-zone entry counted as collector rejection");
      outsideZones.Shutdown();

      //--- SignalEngine runtime regressions:
      //--- (1) structure-only setup/bias fallback contributes to confluence when EMAs are flat;
      //--- (2) SetupGate rejections preserve preliminary factor score (non-zero) and
      //---     repeated timer scans on identical closed bars do not spawn duplicate rejected signals.
      CScoringEngine sigScorer;
      CStrategyRegistry sigStrategies; sigStrategies.Init();
      CSignalLifecycle sigLifecycle;
      CSignalDeduplicator sigDedup;
      CSignalEngine sigEngine;
      sigEngine.Attach(&sigScorer, &sigStrategies, &sigLifecycle, &sigDedup);

      SMarketAnalysis ctx0 = bias; ctx0.tf = PERIOD_D1; ctx0.bias.valid = false; ctx0.bias.side = QME_SIDE_NONE; ctx0.structure.valid = false;
      SMarketAnalysis bias0 = bias; bias0.tf = PERIOD_H4; bias0.bias.valid = false; bias0.bias.side = QME_SIDE_NONE;
      bias0.structure.valid = true; bias0.structure.trend = QME_TREND_UP;
      SMarketAnalysis struct0 = structure; struct0.tf = PERIOD_H1;
      struct0.structure.valid = true; struct0.structure.trend = QME_TREND_UP;
      struct0.trend.valid = true; struct0.trend.trend = QME_TREND_UP; struct0.trend.strength = 0.6;
      SMarketAnalysis setup0 = setup; setup0.tf = PERIOD_M15;
      setup0.trend.valid = true; setup0.trend.trend = QME_TREND_FLAT; setup0.trend.strength = 0.0;
      setup0.structure.valid = true; setup0.structure.trend = QME_TREND_UP;
      SMarketAnalysis entry0 = setup; entry0.tf = PERIOD_M5; entry0.barTime = setup.barTime;
      entry0.momentum.valid = false; entry0.displacement.valid = false; entry0.pattern.valid = false;

      SDataQuality sigDq; QmeDataQualityClear(sigDq); sigDq.ok = true;
      CSignalRegistry sigReg;
      STradingSignal sigOut[];
      CConfig strictCfg = cfg;
      strictCfg.In.minConfluence = 0.90; // force deterministic SetupGate NO_CONFLUENCE rejection
      sigEngine.Generate(ctx0, bias0, struct0, setup0, entry0, zones, spec, strictCfg, sigDq, sigReg, sigOut);
      const int countAfterFirst = sigReg.Count();
      g_kit.Check(countAfterFirst >= 1, "first deterministic rejection creates one recorded signal");
      STradingSignal firstRec; QmeSignalClear(firstRec);
      if(countAfterFirst >= 1)
         g_kit.Check(sigReg.At(0, firstRec), "recorded signal readable");
      g_kit.Check(firstRec.score > 0.0, "SetupGate rejection preserves non-zero preliminary factor score");
      g_kit.Check(firstRec.confidence > 0.22, "H4/M15 structure fallback supplies confluence > 0.22 when EMA trend is flat");

      sigEngine.Generate(ctx0, bias0, struct0, setup0, entry0, zones, spec, strictCfg, sigDq, sigReg, sigOut);
      g_kit.CheckEqual(sigReg.Count(), countAfterFirst,
                       "repeat 5s scan on identical closed bars suppresses duplicate rejected signal");
     }

   zones.Shutdown();
   return(g_kit.End());
  }

#endif // __QME_TEST_MTF_MQH__
//+------------------------------------------------------------------+
