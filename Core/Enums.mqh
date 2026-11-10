//+------------------------------------------------------------------+
//|                                                      Enums.mqh   |
//|  QuantumMarketEngine — every enumeration used by the engine.      |
//|  OWNERSHIP: header only. All enums are plain (non-scoped) so the  |
//|  MQL5 compiler can use them as array indices without casts.       |
//+------------------------------------------------------------------+
#ifndef __QME_CORE_ENUMS_MQH__
#define __QME_CORE_ENUMS_MQH__

//--- trade direction. Numeric values are intentional (+1/-1) so that
//--- price arithmetic (entry + dir*slDistance) stays branch-free.
enum ENUM_QME_SIDE
  {
   QME_SIDE_NONE = 0,
   QME_SIDE_BUY  = 1,
   QME_SIDE_SELL = -1
  };

//--- account classification (never authorization by itself)
enum ENUM_QME_ACCOUNT_MODE
  {
   QME_ACC_UNKNOWN = 0,
   QME_ACC_DEMO    = 1,
   QME_ACC_CONTEST = 2,
   QME_ACC_REAL    = 3
  };

//--- market regime
enum ENUM_QME_REGIME
  {
   QME_REGIME_UNKNOWN = 0,
   QME_REGIME_TREND_UP,
   QME_REGIME_TREND_DOWN,
   QME_REGIME_RANGE,
   QME_REGIME_EXPANSION,
   QME_REGIME_CONTRACTION
  };

//--- directional trend state
enum ENUM_QME_TREND
  {
   QME_TREND_UNKNOWN = 0,
   QME_TREND_UP,
   QME_TREND_DOWN,
   QME_TREND_FLAT
  };

//--- volatility state
enum ENUM_QME_VOLATILITY
  {
   QME_VOL_UNKNOWN = 0,
   QME_VOL_LOW,
   QME_VOL_NORMAL,
   QME_VOL_HIGH,
   QME_VOL_EXTREME
  };

//--- trading session (computed from GMT)
enum ENUM_QME_SESSION
  {
   QME_SESSION_UNKNOWN = 0,
   QME_SESSION_ASIA,
   QME_SESSION_LONDON,
   QME_SESSION_NEWYORK,
   QME_SESSION_OVERLAP,
   QME_SESSION_OFFHOURS
  };

//--- where a zone came from
enum ENUM_QME_ZONE_SOURCE
  {
   QME_ZONE_SRC_NONE = 0,
   QME_ZONE_SRC_ORDER_BLOCK,
   QME_ZONE_SRC_FVG,
   QME_ZONE_SRC_LIQUIDITY,
   QME_ZONE_SRC_SUPPORT_RESISTANCE,
   QME_ZONE_SRC_PREMIUM_DISCOUNT,
   QME_ZONE_SRC_SESSION_RANGE,
   QME_ZONE_SRC_VOLUME_PROFILE,
   QME_ZONE_SRC_PDH_PDL,
   QME_ZONE_SRC_COUNT
  };

//--- zone lifecycle
enum ENUM_QME_ZONE_STATE
  {
   QME_ZSTAT_FRESH = 0,
   QME_ZSTAT_TESTED,
   QME_ZSTAT_MITIGATED,
   QME_ZSTAT_INVALIDATED,
   QME_ZSTAT_EXPIRED
  };

//--- signal lifecycle (exact states required by specification)
enum ENUM_QME_SIGNAL_STATE
  {
   QME_SIG_NONE = 0,
   QME_SIG_DETECTED,
   QME_SIG_EVALUATING,
   QME_SIG_APPROVED,
   QME_SIG_EXECUTION_PENDING,
   QME_SIG_EXECUTED,
   QME_SIG_MONITORING,
   QME_SIG_CLOSED,
   QME_SIG_REJECTED,
   QME_SIG_EXPIRED,
   QME_SIG_INVALIDATED,
   QME_SIG_EXECUTION_FAILED,
   QME_SIG_CANCELLED
  };

//--- explicit rejection reasons (never a silent drop)
enum ENUM_QME_REJECT
  {
   QME_REJ_NONE = 0,
   QME_REJ_NOT_TRADABLE,
   QME_REJ_NO_DATA,
   QME_REJ_STALE_DATA,
   QME_REJ_DATA_QUALITY,
   QME_REJ_SYMBOL_DISABLED,
   QME_REJ_LOW_SCORE,
   QME_REJ_NO_CONFLUENCE,
   QME_REJ_NO_STRUCTURE,
   QME_REJ_SPREAD,
   QME_REJ_SESSION,
   QME_REJ_NEWS_WINDOW,
   QME_REJ_DISABLED_BY_CONFIG,
   QME_REJ_RISK_PER_TRADE,
   QME_REJ_DAILY_LOSS,
   QME_REJ_DRAWDOWN,
   QME_REJ_MAX_POSITIONS,
   QME_REJ_SYMBOL_EXPOSURE,
   QME_REJ_PORTFOLIO_EXPOSURE,
   QME_REJ_CORRELATION,
   QME_REJ_CONSECUTIVE_LOSSES,
   QME_REJ_RR,
   QME_REJ_SL_INVALID,
   QME_REJ_TP_INVALID,
   QME_REJ_VOLUME_INVALID,
   QME_REJ_MARGIN,
   QME_REJ_MARKET_CLOSED,
   QME_REJ_DUPLICATE_SIGNAL,
   QME_REJ_DUPLICATE_POSITION,
   QME_REJ_ACCOUNT_MODE,
   QME_REJ_TRADING_NOT_AUTHORIZED,
   QME_REJ_PERMISSION_TERMINAL,
   QME_REJ_PERMISSION_EXPERT,
   QME_REJ_PERMISSION_SYMBOL,
   QME_REJ_ACCOUNT_PERMISSION,
   QME_REJ_LOGIN_MISMATCH,
   QME_REJ_EXECUTION_FAILED,
   QME_REJ_BROKER_REJECTED,
   QME_REJ_EXPIRED,
   QME_REJ_INVALIDATED,
   QME_REJ_INTERNAL
  };

//--- log severity (ordered)
enum ENUM_QME_SEVERITY
  {
   QME_LOG_TRACE = 0,
   QME_LOG_DEBUG,
   QME_LOG_INFO,
   QME_LOG_WARN,
   QME_LOG_ERROR,
   QME_LOG_CRITICAL,
   QME_LOG_COUNT
  };

//--- entry mechanics
enum ENUM_QME_ENTRY_TYPE
  {
   QME_ENTRY_MARKET = 0,
   QME_ENTRY_LIMIT,
   QME_ENTRY_STOP
  };

//--- execution state machine (live, before/after broker confirmation)
enum ENUM_QME_EXEC_STATE
  {
   QME_EXEC_NONE = 0,
   QME_EXEC_AUTHORIZED,
   QME_EXEC_REQUEST_BUILT,
   QME_EXEC_SENT,
   QME_EXEC_CONFIRMED,
   QME_EXEC_FAILED,
   QME_EXEC_UNKNOWN_STATE,
   QME_EXEC_RECONCILED
  };

//--- structure events
enum ENUM_QME_STRUCT_EVENT
  {
   QME_STRUCT_NONE = 0,
   QME_STRUCT_BOS_UP,
   QME_STRUCT_BOS_DOWN,
   QME_STRUCT_MSS_UP,
   QME_STRUCT_MSS_DOWN,
   QME_STRUCT_BREAKOUT_CONFIRMED,
   QME_STRUCT_BREAKOUT_FAILED
  };

//--- candle pattern identifiers (explicit + testable)
enum ENUM_QME_CANDLE_PATTERN
  {
   QME_CANDLE_NONE = 0,
   QME_CANDLE_BULL_ENGULF,
   QME_CANDLE_BEAR_ENGULF,
   QME_CANDLE_BULL_PIN,
   QME_CANDLE_BEAR_PIN,
   QME_CANDLE_INSIDE_BAR,
   QME_CANDLE_OUTSIDE_BAR,
   QME_CANDLE_STRONG_BULL,
   QME_CANDLE_STRONG_BEAR,
   QME_CANDLE_REJECTION_BULL,
   QME_CANDLE_REJECTION_BEAR,
   QME_CANDLE_DOJI
  };

//--- internal event types travelling on the EventBus
enum ENUM_QME_EVENT
  {
   QME_EVT_NONE = 0,
   QME_EVT_INIT,
   QME_EVT_TICK,
   QME_EVT_TIMER,
   QME_EVT_BAR_CLOSE,
   QME_EVT_SCAN_START,
   QME_EVT_SCAN_END,
   QME_EVT_SIGNAL_DETECTED,
   QME_EVT_SIGNAL_APPROVED,
   QME_EVT_SIGNAL_REJECTED,
   QME_EVT_SIGNAL_EXPIRED,
   QME_EVT_RISK_BREACH,
   QME_EVT_ORDER_SENT,
   QME_EVT_TRADE_TRANSACTION,
   QME_EVT_POSITION_UPDATE,
   QME_EVT_HEALTH,
   QME_EVT_ERROR,
   QME_EVT_SHUTDOWN,
   QME_EVT_COUNT
  };

//--- explainable scoring factors. Used as fixed array indices.
enum ENUM_QME_FACTOR
  {
   QME_F_HTF_BIAS = 0,
   QME_F_STRUCTURE,
   QME_F_LIQUIDITY,
   QME_F_SWEEP,
   QME_F_DISPLACEMENT,
   QME_F_BOS,
   QME_F_MSS,
   QME_F_ORDER_BLOCK,
   QME_F_FVG,
   QME_F_PREMIUM_DISCOUNT,
   QME_F_MOMENTUM,
   QME_F_VOLATILITY,
   QME_F_SESSION,
   QME_F_ENTRY_CONFIRM,
   QME_F_COUNT
  };

//--- correlation groups: factors inside one group must not be double-counted
enum ENUM_QME_FACTOR_FAMILY
  {
   QME_FAM_DIRECTION = 0,
   QME_FAM_STRUCTURE,
   QME_FAM_LIQUIDITY,
   QME_FAM_IMBALANCE,
   QME_FAM_MOMENTUM,
   QME_FAM_CONTEXT,
   QME_FAM_COUNT
  };

//--- asset class, used to tune thresholds without per-symbol hard-coding
enum ENUM_QME_ASSET
  {
   QME_ASSET_UNKNOWN = 0,
   QME_ASSET_FX,
   QME_ASSET_METAL,
   QME_ASSET_INDEX,
   QME_ASSET_ENERGY,
   QME_ASSET_CRYPTO,
   QME_ASSET_STOCK,
   QME_ASSET_COUNT
  };

//--- classification of a broker retcode for retry decisions
enum ENUM_QME_RETRY_CLASS
  {
   QME_RETRY_NO = 0,          // do not retry (permanent)
   QME_RETRY_TRANSIENT,       // safe to retry after delay (requote/price change)
   QME_RETRY_NEVER_IDEMPOTENT // must never be blindly repeated (e.g. timeout)
  };

#endif // __QME_CORE_ENUMS_MQH__
//+------------------------------------------------------------------+
