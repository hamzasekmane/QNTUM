//+------------------------------------------------------------------+
//|                                           Data/AssetClassTuning   |
//|  QuantumMarketEngine — asset-class parameters.                     |
//|                                                                   |
//|  Different instruments have different natural volatility, spread    |
//|  and stop geometry. Instead of hard-coding per symbol, thresholds   |
//|  are expressed RELATIVE to the instrument's own ATR and then        |
//|  scaled by the asset class.                                        |
//|                                                                   |
//|  Detection is a documented heuristic over SYMBOL_PATH/name; it is    |
//|  advisory only and never grants trading permission.                 |
//+------------------------------------------------------------------+
#ifndef __QME_DATA_ASSETTUNING_MQH__
#define __QME_DATA_ASSETTUNING_MQH__

#include "../Core/Enums.mqh"
#include "../Core/Utils.mqh"

//--- helper kept static-free for clarity: all six characters must be letters
bool IsFxLetter(const string s)
  {
   for(int i = 0; i < 6; i++)
     {
      const int ch = StringGetCharacter(s, i);
      if(ch < 'A' || ch > 'Z') return(false);
     }
   return(true);
  }

struct SAssetTuning
  {
   double            atrLowRatio;      // ATR/ATRavg below -> low volatility
   double            atrHighRatio;     // ATR/ATRavg above -> high volatility
   double            spreadAtrCap;     // max spread as fraction of ATR
   double            displacementMult; // body must exceed N * avg body
   double            slAtrMult;        // default stop distance in ATR
   double            minRRScalar;      // multiplies the configured minRR
   int               swingRightBars;   // confirmation delay for swings
   double            zoneMinHeightAtr; // zones thinner than this are noise
  };

class CAssetClassTuning
  {
public:
   static ENUM_QME_ASSET Detect(const string symbol, const string path, const string description);
   static string     Name(const ENUM_QME_ASSET a);
   static void       Get(const ENUM_QME_ASSET a, SAssetTuning &t);
  };

//------------------------------------------------------------------//
ENUM_QME_ASSET CAssetClassTuning::Detect(const string symbol, const string path, const string description)
  {
   const string s = QmeUpper(symbol);
   const string p = QmeUpper(path);
   const string d = QmeUpper(description);
   const string all = s + " " + p + " " + d;

   if(StringFind(all, "CRYPTO") >= 0 || StringFind(all, "BITCOIN") >= 0 ||
      StringFind(all, "ETH") >= 0)
      return(QME_ASSET_CRYPTO);

   if(StringFind(all, "METAL") >= 0 || StringFind(all, "GOLD") >= 0 ||
      StringFind(all, "SILVER") >= 0 || StringFind(s, "XAU") >= 0 ||
      StringFind(s, "XAG") >= 0 || StringFind(s, "XPT") >= 0)
      return(QME_ASSET_METAL);

   if(StringFind(all, "ENERGY") >= 0 || StringFind(all, "OIL") >= 0 ||
      StringFind(s, "WTI") >= 0 || StringFind(s, "BRENT") >= 0 ||
      StringFind(s, "NGAS") >= 0)
      return(QME_ASSET_ENERGY);

   if(StringFind(all, "INDEX") >= 0 || StringFind(all, "INDICES") >= 0 ||
      StringFind(s, "US30") >= 0 || StringFind(s, "NAS") >= 0 ||
      StringFind(s, "SPX") >= 0 || StringFind(s, "DAX") >= 0 ||
      StringFind(s, "GER") >= 0 || StringFind(s, "UK100") >= 0)
      return(QME_ASSET_INDEX);

   if(StringFind(all, "FOREX") >= 0 || StringFind(p, "FX") >= 0)
      return(QME_ASSET_FX);

   //--- 6-letter FX pair with no explicit path hint
   if(StringLen(s) == 6 && StringFind(s, ".") < 0 && StringFind(s, "_") < 0 &&
      IsFxLetter(s))
      return(QME_ASSET_FX);

   if(StringFind(all, "STOCK") >= 0 || StringFind(all, "EQUITY") >= 0 ||
      StringFind(all, "SHARE") >= 0)
      return(QME_ASSET_STOCK);

   return(QME_ASSET_UNKNOWN);
  }

//------------------------------------------------------------------//
string CAssetClassTuning::Name(const ENUM_QME_ASSET a)
  {
   switch(a)
     {
      case QME_ASSET_FX:     return("FX");
      case QME_ASSET_METAL:  return("METAL");
      case QME_ASSET_INDEX:  return("INDEX");
      case QME_ASSET_ENERGY: return("ENERGY");
      case QME_ASSET_CRYPTO: return("CRYPTO");
      case QME_ASSET_STOCK:  return("STOCK");
     }
   return("UNKNOWN");
  }

//------------------------------------------------------------------//
void CAssetClassTuning::Get(const ENUM_QME_ASSET a, SAssetTuning &t)
  {
   //--- conservative defaults, overridden per class below
   t.atrLowRatio       = 0.70;
   t.atrHighRatio      = 1.60;
   t.spreadAtrCap      = 0.15;
   t.displacementMult  = 1.50;
   t.slAtrMult         = 1.20;
   t.minRRScalar       = 1.00;
   t.swingRightBars    = QME_SWING_RIGHT_BARS;
   t.zoneMinHeightAtr  = 0.15;

   switch(a)
     {
      case QME_ASSET_FX:
         t.atrLowRatio = 0.70; t.atrHighRatio = 1.60;
         t.spreadAtrCap = 0.10; t.slAtrMult = 1.10;
         t.displacementMult = 1.40; t.zoneMinHeightAtr = 0.12;
         break;
      case QME_ASSET_METAL:
         t.atrLowRatio = 0.65; t.atrHighRatio = 1.80;
         t.spreadAtrCap = 0.12; t.slAtrMult = 1.30;
         t.displacementMult = 1.50; t.zoneMinHeightAtr = 0.15;
         break;
      case QME_ASSET_INDEX:
         t.atrLowRatio = 0.60; t.atrHighRatio = 1.70;
         t.spreadAtrCap = 0.15; t.slAtrMult = 1.25;
         t.displacementMult = 1.55; t.zoneMinHeightAtr = 0.18;
         break;
      case QME_ASSET_ENERGY:
         t.atrLowRatio = 0.55; t.atrHighRatio = 1.90;
         t.spreadAtrCap = 0.20; t.slAtrMult = 1.50;
         t.displacementMult = 1.70; t.zoneMinHeightAtr = 0.22;
         break;
      case QME_ASSET_CRYPTO:
         t.atrLowRatio = 0.50; t.atrHighRatio = 2.00;
         t.spreadAtrCap = 0.25; t.slAtrMult = 1.60;
         t.displacementMult = 1.80; t.minRRScalar = 1.15;
         t.zoneMinHeightAtr = 0.25;
         break;
      case QME_ASSET_STOCK:
         t.atrLowRatio = 0.65; t.atrHighRatio = 1.80;
         t.spreadAtrCap = 0.20; t.slAtrMult = 1.35;
         t.displacementMult = 1.60; t.zoneMinHeightAtr = 0.20;
         break;
      case QME_ASSET_UNKNOWN:
         //--- unknown assets get the strictest spread and geometry limits
         t.spreadAtrCap = 0.10;
         t.minRRScalar = 1.20;
         break;
     }
   }

#endif // __QME_DATA_ASSETTUNING_MQH__
//+------------------------------------------------------------------+
