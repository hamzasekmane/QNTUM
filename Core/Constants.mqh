//+------------------------------------------------------------------+
//|                                                   Constants.mqh  |
//|  QuantumMarketEngine — compile-time constants and fixed limits.  |
//|  OWNERSHIP: header only, no state, no ownership.                 |
//+------------------------------------------------------------------+
#ifndef __QME_CORE_CONSTANTS_MQH__
#define __QME_CORE_CONSTANTS_MQH__

#define QME_PRODUCT_NAME       "QuantumMarketEngine"
#define QME_VERSION            "1.0.0"
#define QME_STATE_SCHEMA       1

//--- capacity limits (fixed, so no runtime allocation surprises) ---
const int    QME_MAX_SYMBOLS            = 32;   // scanner capacity
const int    QME_MAX_TIMEFRAMES         = 8;    // M1..W1
const int    QME_MAX_ZONES_PER_TF       = 96;
const int    QME_MAX_ZONES_PER_SYMBOL   = 512;
const int    QME_MAX_SWINGS             = 256;
const int    QME_MAX_LIQUIDITY_LEVELS   = 128;
const int    QME_MAX_SIGNALS            = 64;   // live registry capacity
const int    QME_MAX_CANDIDATES         = 32;   // per symbol per scan
const int    QME_MAX_POSITIONS_MONITORED= 128;
const int    QME_MAX_EVENT_QUEUE        = 512;
const int    QME_MAX_LOG_RING           = 512;
const int    QME_MAX_FINGERPRINTS       = 512;  // idempotency memory
const int    QME_MAX_HISTORY            = 256;  // closed-signal history
const int    QME_MAX_TRACKED_POSITIONS  = 64;   // persisted position records
const int    QME_STATE_VERSION          = 1;    // persisted format version
const int    QME_MAX_FUNNEL_STAGES      = 16;
const int    QME_MAX_PROFILER_SECTIONS  = 32;
const int    QME_MAX_ALERTS             = 64;

//--- data pipeline ---
const int    QME_MIN_BARS_REQUIRED      = 64;   // hard floor for any decision timeframe
const int    QME_SCAN_BARS              = 20;   // bars scanned for structure/liquidity events
const int    QME_DEFAULT_BARS_CONTEXT   = 400;
const int    QME_SWING_LEFT_BARS        = 2;
const int    QME_SWING_RIGHT_BARS       = 2;    // confirmation delay: never repaint

//--- numeric tolerances ---
const double QME_EPSILON                = 1e-10;
const double QME_PRICE_EPS              = 1e-8;
const double QME_VOLUME_EPS             = 1e-8;
const double QME_MIN_VOLUME_SAFETY      = 0.01; // never size below 1% of broker minimum

//--- scoring / decision defaults ---
const double QME_SCORE_MAX              = 100.0;
const double QME_SCORE_MIN_DEFAULT      = 55.0;
const double QME_MIN_RR_DEFAULT         = 1.5;

//--- persistence ---
const string QME_BUILD_TAG              = "QME 1.0.0 (phase 10)";
const string QME_STATE_FOLDER           = "QME";
const string QME_STATE_FILE_PREFIX      = "qme_state_";
const string QME_SIGNAL_FILE_PREFIX     = "qme_signals_";
const string QME_JOURNAL_FILE_PREFIX    = "qme_journal_";
const string QME_ORDER_COMMENT          = "QME";
const string QME_LOG_FILE               = "QME\\qme.log";
const int    QME_STATE_FIELD_VERSION    = 1;

//--- strings used by the dashboard ---------------------------------
const string QME_TAG                    = "[QME]";

#endif // __QME_CORE_CONSTANTS_MQH__
//+------------------------------------------------------------------+
