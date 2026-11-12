# تدقيق مسار الدخول — 2026-11-11

## الحكم التنفيذي

أبرز عائق ظاهر في سجلات MT5 كان `scanner valid=0`، ووجدت في المصدر بوابة بيانات كانت تشترط اكتمال كل تحليل هيكلي/سيولة/اتجاه/انحياز في كل إطار. كذلك كان هناك توافق HTF إلزامي افتراضيًا، وفقدان D1 من مسار الإشارة، وfingerprint rejection يمنع إعادة تقييم الإشارة المرفوضة. أُصلحت هذه النقاط وأضيفت أسباب حجب مفصلة؛ يلزم تشغيل MT5 جديد لمطابقة الدليل.

وجدت أيضًا أن `OnTimer` كان يدير المراكز فقط ولا يبدأ دورة المسح؛ وهذا يوقف تعدد الرموز إذا صمت رمز الشارت. أضيفت دورة مؤقت آمنة تستخدم نفس scheduler/بوابات Cycle. وتحذير ledger يفسره بقاء التسجيل في كائن dispatcher عام عند إعادة Init؛ أضيف reset قبل الربط.

Exposure كان يُحسب من `volume*contractSize*price` بعملة التسعير الخام ثم يقارن بـequity بعملة الحساب؛ استُبدل بتقدير account-currency من tick value/tick size. لكن الحدود الحالية قد تظل مانعة فعليًا: عند equity ≈6620 USD، أقل حجم XAUUSD=0.01 مع tickValue=$1/tickSize=$0.01 وسعر ~$4038 يعطي notional ≈$4038 (≈61% equity)، أعلى من maxSymbolExposure=5% ($331). EURUSD 0.01 lot عند ~$1.10 يعطي ≈$1100 (≈16.6% equity)، أيضًا أعلى من 5%. لم أرفع الحدود؛ هذه الإعدادات تحظر أصغر lot، وتحتاج قرارًا مدروسًا عن معنى سقف التعرض قبل التداول.

كما أن سجل المستخدم يظهر `analysisOnly=YES`, `demoSwitch=NO`, `sent=0`: لذلك عدم التنفيذ هناك متوقع ومقصود، ولا ينبغي تجاوز مفاتيح السلامة لإجبار صفقات.

## خريطة التبعيات والتدفق

`QME_Main.mq5` (مدخل EA/المؤقت/Watchdog/لوحة) → `CEngine::Init/Cycle` → `CMarketData` و`CScanner` → لكل رمز × D1/H4/H1/M15/M5: `CTimeframeContext` + `CBarSeries` + مؤشرات → `CStructureEngine`, `CLiquidityEngine`, `CLiquiditySweep`, BOS/MSS, OB/FVG, Premium/Discount, عوامل السوق → `CZoneEngine` → `CSignalEngine` → `CandidateCollector` (مرشح لكل جهة) → `CandidateClusterer` → `CMtfConfluenceEngine` → `CSetupEngine` → `CEntryEngine` → `CScoringEngine` + `SignalQualityEngine` → `CSignalRegistry`/دورة حياة/إزالة التكرار → `CDecisionEngine` → `CRiskEngine`/`CPreTradeValidator` → `CExecutionGateway` → `COrderManager`/بوابة الوسيط → تتبع مركز/حالة/Journal/Checkpoint.

وحدات الجودة/الحواجز تشمل `CDataQualityGuard`, `CCausalValidator`, `CSystemWatchdog`, `CTradingPermissions`, `CPortfolioRisk`, `CExposureManager`, `CConsecutiveLossGuard`, `CIdempotencyGuard`, `CStateRecovery`. المشروع يحوي 191 ملف MQL مصدرًا و21 برنامج اختبار MQL؛ أدوات `mql5check`, `mql5fields`, `mql5calls` فحوص heuristic وليست compiler.

## النتائج والإصلاحات على الفرع

1. **بوابة توليد الفرص:** `CEngine::Cycle` لا يستدعي الإشارات إلا إذا `rt.snapshot.dataValid`. سابقًا كانت `snapshot.dataValid` تتطلب `analysis.valid` في كل واحد من H4/H1/M15/M5، و`analysis.valid` نفسه يشترط structure + liquidity + trend + bias. غياب عامل تحليلي واحد في أي إطار كان يعادل إسقاط runtime كله، رغم أن الحقول الاختيارية مدعومة downstream. أزيل شرط اكتمال التحليل من بوابة صلاحية البيانات؛ تظل بيانات الشموع المغلقة، فحوص الجودة، وحداثة tick مطلوبة لكل إطار. `BuildAnalysis` الآن يعلن جاهزية الإطار عند وجود OHLC/ATR/وقت صالحين؛ وتظل `analysis.valid` وصفًا لاكتمال التحليل.
2. **سبب الحجب:** الماسح الآن يضيف أسباب عدم الجاهزية لكل إطار (`series/context/quality/tick`) إلى تحذير Scanner و`Describe()` بدل `valid=0` بلا تفسير. عند إعادة الاختبار نحتاج نص هذه الأسباب؛ لا تتضمن بيئة التطوير بيانات وسيط لعرض السبب الفعلي.
3. **Top-down:** كان D1 (slot 0) لا يدخل `Generate` أصلًا؛ كان المستخدم فعليًا H4 bias + H1 structure + M15 setup + M5 entry. أُدخل D1 كأعلى view، وH4/H1/M15/M5 تبقى views مستقلة. تغيير default `requireHtfAlignment=false` يجعل D1 عامل confluence مرجّحًا وليس veto مطلقًا؛ الحد الأدنى للـconfluence والـscore والبوابات الهيكلية تبقى قائمة.
4. **إعادة تهيئة ledger:** `CEventDispatcher` يحتفظ بتسجيلات الـsink طوال عمر كائن EA العام، بينما `CEngine` قد يعاد تهيئته بعد تعديل المدخلات دون إعادة إنشاء الكائن. كان الاسم `ledger` حينها duplicate، فيفشل AddSink. أضيف `Reset()` ويستدعى قبل الربط في كل Init، مع اختبار MQL لإعادة التسجيل.
5. **التحليلات الاختيارية:** BuildViews وCandidateCollector لا يلغيان دليل bias/structure لمجرد أن `SMarketAnalysis.valid` الإجمالي false، وEntryEngine يشترط بيانات سعر/ATR/شمعة بدل اكتمال كل وحدات التحليل على M5. يبقى setup محتاجًا بنية قابلة للاستخدام، مناطق، جودة، تأكيد دخول ودرجتين مستقلتين على الأقل.
6. **إشارات ومخاطر:** ما زال scoring ترتيبًا heuristic من 0–100 وليس احتمال ربح. لا تغيير على بوابات `analysisOnly`, صلاحيات الحساب، قياس المخاطر، active orders أو SL. الإشارات التي تولد في التحليل لا تعني أن التداول مصرح. إعداد `enableRealTrading=true` مع expected login=0 يسبب فشل init المقصود؛ أطفئه للتشغيل التحليلي/DEMO.

## سجل التشغيل الذي أرسله المستخدم

- `INIT FAILED: enableRealTrading requires expectedRealAccountLogin > 0`: رفض configuration صريح وآمن. لا تُدخل رقمًا لتجاوز الحاجز؛ أعد `InpEnableRealTrading=false`.
- في التشغيل اللاحق نجح Init مع `analysisOnly=YES` و`demoSwitch=NO` و`realSwitch=YES`، لكن `scanner valid=0` و`sent=0`. يلزم اختبار build التالي ومراجعة أسباب dataBlock الجديدة. من الأفضل أيضًا إرجاع realSwitch إلى false.
- `event sink 'ledger' could not be registered` ظهر عند إعادة تهيئة EA. عولج بتصفير تسجيلات dispatcher قبل إضافة sink عند كل Init، وأضيف اختبار إعادة التسجيل؛ يلزم تأكيده في MT5.
- `QATS` مستشار آخر، خارج هذا المشروع. تقريره عن صفقات/ربح/إشارات لا يثبت أداء QME؛ تحكم فيه مستقلاً.

## فلاتر الفرص المتبقية التي قد تقلل العدد

- `CandidateCollector::Collect` يحتاج setup structure صالحًا، Zone نشطة لكل جهة، RR لا يقل عن 2R في أحدث تعديلات السيولة، SL ضمن 4 ATR، ورفض أو انتظار بعض حالات sweep/breakout.
- `CSetupEngine` يطلب توافقًا ≥0.4 واثنين من تأكيدات مستقلة، ويرفض المكان الشديد الخطأ داخل dealing range. `minScore` قائم، و`EntryEngine` يحتاج pattern/momentum/reaction/displacement مناسبًا؛ ثم `SignalQualityEngine` يطبق جودة/سبريد.
- إزالة التكرار/registry/cooldown، سقف الإشارات اليومية، `RuntimeController::MayTrade`، والتحقق من المخاطر/الأوامر المفتوحة ثم صلاحيات execution قد تمنع التنفيذ بعد ظهور setup. يجب استخدام funnel/replay وأسباب الرفض، لا خفض الحدود عشوائيًا.

## تحقق وحالة

أُعيد تشغيل `python3 test_system.py`: 41/41 فحصًا ثابتًا. `git diff --check` وأدوات البنية/الحقول/عدد وسائط الاستدعاءات اجتازت؛ هذه ليست تجميعة MQL. لا MetaEditor/MT5 في بيئة التطوير، واختبارات MQL21 غير منفذة. الخطوة التالية على build 6251: جمّع QME والاختبارات، شغّل على DEMO مع `analysisOnly=true` وREAL switch مغلق، واجمع كامل scanner `data blocked`، funnel counts وأسباب الرفض حتى decision/execution. لا تفعّل تداولًا حيًا أو غير مراقب.
