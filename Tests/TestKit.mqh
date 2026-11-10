//+------------------------------------------------------------------+
//|                                                    Tests/TestKit  |
//|  Minimal test harness for the QME test programs.                     |
//|                                                                   |
//|  Each test is an EA: it runs its assertions in OnInit, prints a       |
//|  PASS/FAIL line per assertion and a summary, then returns             |
//|  INIT_FAILED when anything failed so the tester marks the run as       |
//|  failed. Tests that need market data must SKIP (never pass) when the    |
//|  data is not available.                                             |
//+------------------------------------------------------------------+
#ifndef __QME_TESTKIT_MQH__
#define __QME_TESTKIT_MQH__

#include "../Core/Constants.mqh"
#include "../Core/Utils.mqh"

class CTestKit
  {
private:
   string            m_suite;
   int               m_pass;
   int               m_fail;
   int               m_skip;
   string            m_failures;

public:
                     CTestKit(void) { m_suite = "tests"; m_pass = 0; m_fail = 0; m_skip = 0; m_failures = ""; }

   void              Begin(const string suite) { m_suite = suite; }
   void              Check(const bool cond, const string what);
   void              CheckEqual(const long got, const long want, const string what);
   void              CheckClose(const double got, const double want, const double tol,
                                const string what);
   void              CheckStr(const string got, const string want, const string what);
   void              Skip(const string what);
   int               Passed(void) { return(m_pass); }
   int               Failed(void) { return(m_fail); }
   int               Skipped(void) { return(m_skip); }
   int               End(void);
  };

//------------------------------------------------------------------//
void CTestKit::Check(const bool cond, const string what)
  {
   if(cond)
     {
      m_pass++;
      Print("  PASS  ", what);
      return;
     }
   m_fail++;
   m_failures += "[" + what + "] ";
   Print("  FAIL  ", what);
  }

//------------------------------------------------------------------//
void CTestKit::CheckEqual(const long got, const long want, const string what)
  {
   if(got == want) { Check(true, what); return; }
   m_fail++;
   m_failures += "[" + what + ": " + IntegerToString(got) + " != " +
                 IntegerToString(want) + "] ";
   Print("  FAIL  ", what, " (", got, " != ", want, ")");
  }

//------------------------------------------------------------------//
void CTestKit::CheckClose(const double got, const double want, const double tol,
                          const string what)
  {
   if(MathAbs(got - want) <= tol) { Check(true, what); return; }
   m_fail++;
   m_failures += "[" + what + ": " + DoubleToString(got, 8) + " != " +
                 DoubleToString(want, 8) + "] ";
   Print("  FAIL  ", what, " (", DoubleToString(got, 8), " != ",
         DoubleToString(want, 8), ")");
  }

//------------------------------------------------------------------//
void CTestKit::CheckStr(const string got, const string want, const string what)
  {
   if(got == want) { Check(true, what); return; }
   m_fail++;
   m_failures += "[" + what + ": '" + got + "' != '" + want + "'] ";
   Print("  FAIL  ", what, " ('", got, "' != '", want, "')");
  }

//------------------------------------------------------------------//
void CTestKit::Skip(const string what)
  {
   m_skip++;
   Print("  SKIP  ", what);
  }

//------------------------------------------------------------------//
int CTestKit::End(void)
  {
   Print("=== ", m_suite, ": ", m_pass, " passed, ", m_fail, " failed, ",
         m_skip, " skipped ===");
   if(m_fail > 0)
     {
      Print("FAILURES: ", m_failures);
      return(INIT_FAILED);
     }
   return(INIT_SUCCEEDED);
  }

#endif // __QME_TESTKIT_MQH__
//+------------------------------------------------------------------+
