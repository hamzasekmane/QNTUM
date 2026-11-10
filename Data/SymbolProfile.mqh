//+------------------------------------------------------------------+
//|                                             Data/SymbolProfile    |
//|  QuantumMarketEngine — per-symbol static + slowly-changing facts.   |
//|                                                                   |
//|  Owns the cached SSymbolSpec (re-read periodically because brokers   |
//|  do change stops levels and volume limits intraday) plus the asset   |
//|  class and tuning.                                                 |
//+------------------------------------------------------------------+
#ifndef __QME_DATA_SYMBOLPROFILE_MQH__
#define __QME_DATA_SYMBOLPROFILE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "../Account/SymbolSpecifications.mqh"
#include "AssetClassTuning.mqh"

class CSymbolProfile
  {
private:
   SSymbolSpec       m_spec;
   ENUM_QME_ASSET    m_asset;
   SAssetTuning      m_tuning;
   string            m_symbol;
   datetime          m_lastReload;
   int               m_reloadSec;
   bool              m_ready;
   string            m_error;
   double            m_pip;          // 1 pip in price units
   double            m_typicalSpreadPoints;

public:
                     CSymbolProfile(void);
   bool              Init(const string symbol, string &err);
   bool              Reload(void);

   bool              Ready(void) { return(m_ready); }
   string            Symbol(void) { return(m_symbol); }
   string            LastError(void) { return(m_error); }
   SSymbolSpec       Spec(void) { return(m_spec); }
   void              SpecInto(SSymbolSpec &out) { out = m_spec; }
   ENUM_QME_ASSET    Asset(void) { return(m_asset); }
   SAssetTuning      Tuning(void) { return(m_tuning); }
   double            Pip(void) { return(m_pip); }
   double            TypicalSpreadPoints(void) { return(m_typicalSpreadPoints); }
   int               Digits(void) { return(m_spec.digits); }

   //--- price helpers bound to this symbol's spec
   double            NormalizePrice(const double p) { return(CSymbolSpecifications::NormalizePrice(m_spec, p)); }
   double            NormalizeVolume(const double v) { return(CSymbolSpecifications::NormalizeVolume(m_spec, v)); }
   double            PointsToPrice(const double points) { return(points * m_spec.point); }
   double            PriceToPoints(const double price) { return(QmeSafeDiv(price, m_spec.point, 0.0)); }
   double            ValuePerPriceUnit(void) { return(QmeValuePerPriceUnit(m_spec)); }
   string            Describe(void);
  };

//------------------------------------------------------------------//
CSymbolProfile::CSymbolProfile(void)
  {
   QmeSymbolSpecClear(m_spec);
   m_asset = QME_ASSET_UNKNOWN;
   m_symbol = "";
   m_lastReload = 0;
   m_reloadSec = 60;
   m_ready = false;
   m_error = "";
   m_pip = 0.0;
   m_typicalSpreadPoints = 0.0;
   CAssetClassTuning::Get(QME_ASSET_UNKNOWN, m_tuning);
  }

//------------------------------------------------------------------//
bool CSymbolProfile::Init(const string symbol, string &err)
  {
   err = "";
   m_symbol = symbol;
   if(!Reload())
     {
      err = m_error;
      return(false);
     }
   return(true);
  }

//------------------------------------------------------------------//
bool CSymbolProfile::Reload(void)
  {
   const datetime now = TimeCurrent();
   if(m_lastReload > 0 && now - m_lastReload < m_reloadSec && m_ready)
      return(true);

   m_error = "";
   SSymbolSpec spec;
   if(!CSymbolSpecifications::Load(m_symbol, spec, m_error))
     {
      m_ready = false;
      return(false);
     }
   m_spec = spec;
   m_lastReload = now;
   m_ready = true;

   m_asset = CAssetClassTuning::Detect(m_symbol, m_spec.path, m_spec.description);
   CAssetClassTuning::Get(m_asset, m_tuning);

   //--- pip: 1 pip = 10 points on 3/5-digit FX quotes, otherwise 1 point
   m_pip = m_spec.point;
   if(m_asset == QME_ASSET_FX && (m_spec.digits == 3 || m_spec.digits == 5))
      m_pip = m_spec.point * 10.0;

   //--- typical spread: instantaneous spread is a poor baseline, so use the
   //--- symbol's own current spread only as an initial estimate. It is
   //--- replaced by the observed average once the data layer is warm.
   const double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   if(ask > 0.0 && bid > 0.0 && m_spec.point > 0.0)
      m_typicalSpreadPoints = (ask - bid) / m_spec.point;
   return(true);
  }

//------------------------------------------------------------------//
string CSymbolProfile::Describe(void)
  {
   return(m_symbol + " [" + CAssetClassTuning::Name(m_asset) + "] digits=" +
          IntegerToString(m_spec.digits) + " point=" + DoubleToString(m_spec.point, 8) +
          " tickValue=" + DoubleToString(m_spec.tickValue, 5) +
          " vol=" + DoubleToString(m_spec.volMin, 2) + "/" +
          DoubleToString(m_spec.volMax, 2) + " step=" + DoubleToString(m_spec.volStep, 2) +
          " stops=" + IntegerToString(m_spec.stopsLevelPoints) + "pt");
  }

#endif // __QME_DATA_SYMBOLPROFILE_MQH__
//+------------------------------------------------------------------+
