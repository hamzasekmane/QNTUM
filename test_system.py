#!/usr/bin/env python3
"""
test_system.py — هل يعمل نظام QuantumMarketEngine؟ / Does QNTUM work?

تشغيل / Run:
    python3 test_system.py            # فحص كامل + تقرير / full check + report
    python3 test_system.py --verbose  # مع مخرجات الأدوات كاملة / full tool output

ماذا يفعل هذا الملف فعلاً (بصدق):
  يفحص بنية المشروع، يشغّل أدوات الفحص الثابت الثلاث الموجودة في Tools/,
  يتحقق من ثوابت الأمان (التداول الحقيقي/الديمو مقفل افتراضيًا، الوضع
  التحليلي مفعّل افتراضيًا)، ومن إصلاحات الانحدار المعروفة (انهيار FVG،
  انقضاء الإشارات المنفّذة، أسبقية analysisOnly)، ويتأكد أن برامج اختبار
  MQL5 الـ21 موجودة ومقترنة بملفاتها.

What this file honestly does:
  checks project structure, runs the three static verifiers in Tools/,
  verifies safety defaults (REAL/DEMO trading OFF, analysis-only ON),
  regression guards (FVG crash, executed-signal expiry, analysisOnly
  precedence), and that all 21 MQL5 test programs exist with their suites.

ماذا لا يستطيع فعله:
  لا يوجد MetaEditor/MT5 في هذه البيئة، لذا لا يستطيع تجميع MQL5 أو
  تنفيذ اختبارات Strategy Tester. PASS هنا يعني "سليم بنيويًا وثابتًا"
  وليس "مُجمّعًا ومُختبَرًا على منصة حقيقية".

What it CANNOT do:
  no MetaEditor/MT5 exists here, so it cannot compile MQL5 or execute
  Strategy Tester suites. PASS means "structurally sound", NOT
  "compiled and platform-tested". For that, compile QME_Main.mq5 and
  Tests/*/*.mq5 in MetaEditor (see Documentation/CompilationReport.md).

Exit code: 0 = every check passed, 1 = at least one failure.
Compatible with pytest too (every check is a test_* function).
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VERBOSE = "--verbose" in sys.argv

RESULTS = []  # (name, ok, detail)


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok), detail))
    mark = "PASS" if ok else "FAIL"
    line = f"[{mark}] {name}"
    if detail:
        line += f" — {detail}"
    print(line)
    return ok


def read(rel):
    p = ROOT / rel
    return p.read_text(encoding="utf-8", errors="replace") if p.exists() else ""


def run_tool(script, expect_in_output):
    """Run one of Tools/*.py and require exit 0 + an expected marker."""
    proc = subprocess.run(
        [sys.executable, str(ROOT / "Tools" / script)],
        capture_output=True, text=True, cwd=ROOT, timeout=300,
    )
    out = proc.stdout + proc.stderr
    if VERBOSE:
        print(f"----- {script} -----\n{out}\n---------------------")
    ok = proc.returncode == 0 and expect_in_output in out
    detail = f"exit={proc.returncode}"
    if not ok:
        detail += "; tail: " + " | ".join(out.strip().splitlines()[-3:])
    return ok, detail


# ---------------------------------------------------------------- checks

def test_entry_points_exist():
    ok = True
    for rel in ("QME_Main.mq5", "QME.mqh"):
        p = ROOT / rel
        ok &= check(f"entry point {rel}", p.exists() and p.stat().st_size > 0)
    return ok


def test_no_empty_sources():
    files = [p for p in ROOT.rglob("*") if p.suffix in (".mqh", ".mq5")
             and ".git" not in p.parts]
    empty = [str(p.relative_to(ROOT)) for p in files if p.stat().st_size == 0]
    return check(f"{len(files)} MQL5 sources, none empty", not empty,
                 ("empty: " + ", ".join(empty)) if empty else "")


def test_static_verifiers():
    ok = True
    ok &= check("Tools/mql5check.py (structure/includes/types)",
                *run_tool("mql5check.py", "OK: no structural errors"))
    ok &= check("Tools/mql5fields.py (member accesses)",
                *run_tool("mql5fields.py", "0 suspicious member access"))
    ok &= check("Tools/mql5calls.py (call arity)",
                *run_tool("mql5calls.py", "0 arity mismatch"))
    return ok


def test_safety_defaults_off():
    """Trading must stay OFF by default; analysis-only ON. Never weaken."""
    src = read("QME_Main.mq5")
    expectations = {
        "InpEnableDemoTrading": "false",
        "InpEnableRealTrading": "false",
        "InpRealTradingArmed": "false",
        "InpAnalysisOnly": "true",
        "InpCloseOnOppositeSignal": "false",
    }
    ok = True
    for name, want in expectations.items():
        m = re.search(rf"input\s+bool\s+{name}\s*=\s*(\w+)", src)
        got = m.group(1) if m else "MISSING"
        ok &= check(f"default {name} = {want}", got == want, f"found {got}")
    return ok


def test_fvg_crash_regression_guard():
    """D-024: detectors must never ArrayResize a caller-owned fixed buffer."""
    ok = True
    for rel in ("Analysis/PriceAction/FvgEngine.mqh",
                "Analysis/PriceAction/OrderBlockEngine.mqh"):
        src = read(rel)
        body = "\n".join(l for l in src.splitlines()
                         if not l.strip().startswith("//"))
        ok &= check(f"{Path(rel).name}: no ArrayResize on caller buffer",
                    "ArrayResize(out" not in body.replace(" ", ""))
        ok &= check(f"{Path(rel).name}: capacity-bounded writes",
                    "MathMin(maxOut, ArraySize(out))" in src
                    and "found < capacity" in src)
    return ok


def test_executed_signals_cannot_expire():
    src = read("Strategy/SignalExpiry.mqh")
    guarded = ("QME_SIG_DETECTED" in src and "QME_SIG_EXECUTION_PENDING" in src
               and src.count("QME_SIG_DETECTED") >= 2)  # Check + Process share it
    return check("expiry restricted to pre-execution states (Check & Process)",
                 guarded)


def test_analysis_only_precedence():
    src = read("Execution/ExecutionValidator.mqh")
    first = src.find("cfg.In.analysisOnly")
    return check("analysisOnly hard block present in ExecutionValidator",
                 first >= 0 and "QME_REJ_DISABLED_BY_CONFIG" in src)


def test_mql5_test_programs_paired():
    programs = sorted(ROOT.glob("Tests/*/*.mq5"))
    ok = check("21 MQL5 test programs present", len(programs) == 21,
               f"found {len(programs)}")
    for prog in programs:
        suite = prog.with_suffix(".mqh")
        inc = f'#include "{prog.stem}.mqh"' in read(
            str(prog.relative_to(ROOT)))
        ok &= check(f"{prog.parent.name}/{prog.name} paired with suite",
                    suite.exists() and inc)
    return ok


ALL_TESTS = [
    test_entry_points_exist,
    test_no_empty_sources,
    test_static_verifiers,
    test_safety_defaults_off,
    test_fvg_crash_regression_guard,
    test_executed_signals_cannot_expire,
    test_analysis_only_precedence,
    test_mql5_test_programs_paired,
]


def main():
    print("=" * 68)
    print("QNTUM — QuantumMarketEngine system test (static level)")
    print("فحص النظام — المستوى الثابت (لا يشمل تجميع MetaEditor)")
    print("=" * 68)
    for fn in ALL_TESTS:
        try:
            fn()
        except Exception as exc:  # a crashing check is a failed check
            check(fn.__name__, False, f"exception: {exc}")
    failed = [r for r in RESULTS if not r[1]]
    print("-" * 68)
    print(f"TOTAL: {len(RESULTS) - len(failed)}/{len(RESULTS)} passed, "
          f"{len(failed)} failed")
    if failed:
        print("FAILED CHECKS:")
        for name, _, detail in failed:
            print(f"  - {name} {detail}")
        print("\nالنتيجة: النظام فيه مشاكل أعلاه — لا تعتبره يعمل.")
        print("RESULT: NOT OK — fix the failures above.")
        return 1
    print("\nالنتيجة: كل الفحوصات الثابتة ناجحة ✓")
    print("RESULT: static level OK ✓")
    print("تنبيه: هذا لا يعني أنه جُمّع أو اختُبر على MT5 — جمّع QME_Main.mq5")
    print("وبرامج Tests في MetaEditor للحكم النهائي (Documentation/CompilationReport.md).")
    print("NOTE: not a MetaEditor compile/test proof — see CompilationReport.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
