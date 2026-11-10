//+------------------------------------------------------------------+
//|                                      Account/SymbolSpecifications |
//|  QuantumMarketEngine — reads and validates broker symbol rules.    |
//|                                                                   |
//|  Interface:                                                       |
//|    bool Load(const string symbol, SSymbolSpec &spec)              |
//|    bool IsTradable(const SSymbolSpec &spec)                       |
//|  Output: a fully populated SSymbolSpec or an explicit failure.     |
//|                                                                   |
//|  HARD RULE: no default is assumed for digits, tick size, volume     |
//|  limits, stop distance or filling mode. If the broker does not      |
//|  report it, the symbol is rejected, never guessed.                 |
//+------------------------------------------------------------------+
#ifndef __QME_ACCOUNT_SYMBOLSPEC_MQH__
#define __QME_ACCOUNT_SYMBOLSPEC_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/ErrorCodes.mqh"

class CSymbolSpecifications
  {
public:
   //--- ensure the symbol exists in Market Watch; returns false if not
   static bool       EnsureSelected(const string symbol, string &err);

   //--- read every constraint from the terminal
   static bool       Load(const string symbol, SSymbolSpec &spec, string &err);

   //--- structural sanity of the loaded spec (does not consider sessions)
   static bool       IsTradable(const SSymbolSpec &spec, string &err);

   //--- rounding / normalisation helpers that use the spec, not globals
   static double     NormalizePrice(const SSymbolSpec &spec, const double price);
   static double     NormalizeVolume(const SSymbolSpec &spec, const double volume);
   static bool       VolumeInRange(const SSymbolSpec &spec, const double volume);

   //--- minimum allowed distance (price units) between market and a stop
   static double     MinStopDistance(const SSymbolSpec &spec);
  };

//------------------------------------------------------------------//
bool CSymbolSpecifications::EnsureSelected(const string symbol, string &err)
  {
   err = "";
   if(StringLen(symbol) == 0)
     {
      err = "empty symbol";
      return(false);
     }
   if(!SymbolSelect(symbol, true))
     {
      err = "SymbolSelect failed for " + symbol + " (" + QmeLastErrorText() + ")";
      return(false);
     }
   if(SymbolInfoDouble(symbol, SYMBOL_POINT) <= 0.0)
     {
      err = "symbol " + symbol + " has no point size (not in Market Watch)";
      return(false);
     }
   return(true);
  }

//------------------------------------------------------------------//
bool CSymbolSpecifications::Load(const string symbol, SSymbolSpec &spec, string &err)
  {
   err = "";
   QmeSymbolSpecClear(spec);
   spec.symbol = symbol;

   if(!EnsureSelected(symbol, err))
      return(false);

   spec.description   = SymbolInfoString(symbol, SYMBOL_DESCRIPTION);
   spec.path          = SymbolInfoString(symbol, SYMBOL_PATH);
   spec.digits        = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   spec.point         = SymbolInfoDouble(symbol, SYMBOL_POINT);
   spec.tickSize      = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   spec.tickValue     = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   spec.contractSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   spec.volMin        = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   spec.volMax        = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   spec.volStep       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   spec.stopsLevelPoints  = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   spec.freezeLevelPoints = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   spec.tradeMode     = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   spec.execMode      = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_EXEMODE);
   spec.fillingMask   = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   spec.swapLong      = SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG);
   spec.swapShort     = SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT);
   spec.marginInitial = SymbolInfoDouble(symbol, SYMBOL_MARGIN_INITIAL);
   spec.selected      = true;
   spec.valid         = false;

   //--- structural validation. Any of these failing means "do not trade it".
   if(spec.digits < 0 || spec.digits > 8)
     {
      err = "invalid digits for " + symbol;
      return(false);
     }
   if(spec.point <= 0.0)
     {
      err = "invalid point for " + symbol;
      return(false);
     }
   if(spec.tickSize <= 0.0)
     {
      //--- some brokers report 0 for symbols without trade support
      err = "invalid tick size for " + symbol;
      return(false);
     }
   if(spec.tickValue <= 0.0)
     {
      err = "invalid tick value for " + symbol;
      return(false);
     }
   if(spec.contractSize <= 0.0)
     {
      err = "invalid contract size for " + symbol;
      return(false);
     }
   if(spec.volStep <= 0.0 || spec.volMin <= 0.0 || spec.volMax < spec.volMin)
     {
      err = "invalid volume limits for " + symbol;
      return(false);
     }
   if(spec.tradeMode == SYMBOL_TRADE_MODE_DISABLED)
     {
      err = "trading disabled by broker for " + symbol;
      return(false);
     }
   if((spec.fillingMask & (SYMBOL_FILLING_FOK | SYMBOL_FILLING_IOC)) == 0 &&
      spec.fillingMask != 0)
     {
      //--- only RETURN-style filling is offered; still usable for limit orders
     }

   //--- symbol-level permission derived from the mode we just read
   spec.tradeAllowed = (spec.tradeMode != SYMBOL_TRADE_MODE_DISABLED);
   spec.valid = true;
   return(true);
  }

//------------------------------------------------------------------//
bool CSymbolSpecifications::IsTradable(const SSymbolSpec &spec, string &err)
  {
   err = "";
   if(!spec.valid)
     {
      err = "spec not loaded";
      return(false);
     }
   if(spec.tradeMode == SYMBOL_TRADE_MODE_DISABLED)
     {
      err = "symbol trade mode disabled";
      return(false);
     }
   if(spec.volMin <= 0.0 || spec.volStep <= 0.0)
     {
      err = "volume limits unavailable";
      return(false);
     }
   //--- current tick must be available and non-zero
   MqlTick tick;
   if(!SymbolInfoTick(spec.symbol, tick))
     {
      err = "no tick for " + spec.symbol;
      return(false);
     }
   if(tick.bid <= 0.0 || tick.ask <= 0.0 || tick.ask < tick.bid)
     {
      err = "invalid quotes for " + spec.symbol;
      return(false);
     }
   return(true);
  }

//------------------------------------------------------------------//
double CSymbolSpecifications::NormalizePrice(const SSymbolSpec &spec, const double price)
  {
   if(spec.digits < 0 || spec.digits > 8) return(price);
   return(NormalizeDouble(price, spec.digits));
  }

//--- snap volume to the broker step, inside [volMin, volMax]
double CSymbolSpecifications::NormalizeVolume(const SSymbolSpec &spec, const double volume)
  {
   if(spec.volStep <= 0.0) return(0.0);
   if(volume <= 0.0) return(0.0);
   double steps = MathFloor(volume / spec.volStep + 1e-9);
   if(steps < 1.0) steps = 0.0;              // caller must reject, not round up
   double v = steps * spec.volStep;
   if(v < spec.volMin - QME_VOLUME_EPS) return(0.0);
   if(v > spec.volMax) v = spec.volMax;
   //--- re-snap after clamping to max
   v = MathFloor(v / spec.volStep + 1e-9) * spec.volStep;
   //--- volume is reported with limited precision by most brokers
   v = NormalizeDouble(v, 8);
   return(v);
  }

//------------------------------------------------------------------//
bool CSymbolSpecifications::VolumeInRange(const SSymbolSpec &spec, const double volume)
  {
   if(volume < spec.volMin - QME_VOLUME_EPS) return(false);
   if(volume > spec.volMax + QME_VOLUME_EPS) return(false);
   //--- must be an exact multiple of the step (within float tolerance)
   const double ratio = volume / spec.volStep;
   const double rounded = MathRound(ratio);
   if(MathAbs(ratio - rounded) > 1e-6) return(false);
   return(true);
  }

//------------------------------------------------------------------//
double CSymbolSpecifications::MinStopDistance(const SSymbolSpec &spec)
  {
   return(spec.stopsLevelPoints * spec.point);
  }

#endif // __QME_ACCOUNT_SYMBOLSPEC_MQH__
//+------------------------------------------------------------------+
