#!/usr/bin/env python3
"""
mql5check.py — static consistency verifier for the QuantumMarketEngine sources.

There is no MetaEditor/MQL5 compiler on this host. This tool performs the subset
of checks that CAN be done textually. It is NOT a compiler and does not prove
that the code compiles.

Checks
------
 1. include resolution            every #include "..." path exists
 2. include guards                #ifndef/#define/#endif present for .mqh
 3. brace / paren balance         per file
 4. duplicate type definitions    class/struct/enum defined twice in the project
 5. unknown project types         C*/S*/IQ*/ENUM_QME_* used but never declared
 6. qualified definitions         Class::Method with no declaration in Class
 7. declared-but-undefined        non-inline, non-virtual methods with no body
 8. unknown QME_* identifiers     enum members / consts / #defines used but
                                  never defined anywhere in the project
 9. `input` outside main EA       configuration must be injected, not global
10. unimplemented modules         empty .mqh files still referenced by includes

Usage:  python3 Tools/mql5check.py [--verbose] [--quiet]
Exit code 0 when no errors were found.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_EXT = (".mqh", ".mq5")

INCLUDE_RE   = re.compile(r'^\s*#include\s+"([^"]+)"')
DEFINE_RE    = re.compile(r'^\s*#define\s+([A-Za-z_]\w*)')
CONST_RE     = re.compile(r'^\s*const\s+[\w:]+\s+([A-Za-z_]\w*)\s*=')
GLOBALPTR_RE = re.compile(r'^\s*([A-Za-z_]\w*)\s*\*\s*([A-Za-z_]\w*)\s*=\s*NULL\s*;')
TYPE_RE      = re.compile(r'^\s*(class|struct)\s+([A-Za-z_]\w*)')
ENUM_RE      = re.compile(r'^\s*enum\s+([A-Za-z_]\w*)')
QUALIFIED_RE = re.compile(r'^\s*(?:static\s+)?[\w:<>\*&\s]*?\b([A-Za-z_]\w*)::([A-Za-z_]\w*)\s*\(')
MEMBER_RE    = re.compile(r'^\s*(?:static\s+|virtual\s+)*[A-Za-z_][\w:<>*&\s]*?\b([A-Za-z_]\w*)\s*\(')
FUNC_RE      = re.compile(r'^\s*(?:static\s+)?[A-Za-z_][\w:<>\*&]*\s+([A-Za-z_]\w*)\s*\(')

KEYWORDS = {'if', 'for', 'while', 'switch', 'return', 'else', 'case', 'sizeof',
            'delete', 'new', 'Print', 'printf'}

# project type naming conventions (PascalCase after a prefix char)
PROJECT_TYPE = re.compile(r'^(?:C[A-Z][a-z]\w*|S[A-Z][a-z]\w*|IQ[A-Z]\w*|ENUM_QME_\w+)$')
QME_TOKEN    = re.compile(r'\b(QME_[A-Z0-9_]+)\b')


def strip_comments(text):
    """Blank out comments and string literals, preserving line structure."""
    out, i, n = [], 0, len(text)
    line_comment = block_comment = in_str = False
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ''
        if line_comment:
            if c == '\n':
                line_comment = False
                out.append(c)
            else:
                out.append(' ')
        elif block_comment:
            if c == '*' and nxt == '/':
                out.append('  '); i += 1; block_comment = False
            elif c == '\n':
                out.append('\n')
            else:
                out.append(' ')
        elif in_str:
            if c == '\\' and i + 1 < n:
                out.append('  ' if text[i + 1] != '\n' else ' \n'); i += 1
            elif c == '"':
                in_str = False; out.append(' ')
            elif c == '\n':
                out.append('\n')
            else:
                out.append(' ')
        else:
            if c == '/' and nxt == '/':
                out.append('  '); i += 1; line_comment = True
            elif c == '/' and nxt == '*':
                out.append('  '); i += 1; block_comment = True
            elif c == '"':
                in_str = True; out.append(' ')
            elif c == "'":
                # character literal
                out.append(' ')
                j = i + 1
                while j < n and text[j] != "'":
                    j += 1
                i = j
            else:
                out.append(c)
        i += 1
    return ''.join(out)


class Source:
    def __init__(self, path):
        self.path = path
        self.rel = os.path.relpath(path, ROOT).replace(os.sep, '/')
        with open(path, encoding='utf-8', errors='replace') as f:
            self.raw = f.read()
        self.empty = len(self.raw.strip()) == 0
        self.text = strip_comments(self.raw)
        self.lines = self.text.split('\n')
        self.includes = []
        self.types = {}
        self.enum_members = set()
        self.defines = set()
        self.consts = set()
        self.global_ptrs = set()
        self.methods = {}                    # class -> set(methods)
        self.inline_bodies = set()           # (class, method) with inline body
        self.method_defs = {}                # class -> set(methods)
        self.functions = set()
        self.interface_classes = set()


def parse(src):
    depth = 0
    cur_class = None
    class_depth = None
    enum_pending = False
    pending_inline = None      # (class, method) waiting for '{' on the next line

    for raw in src.lines:
        s = raw.strip()
        if not s:
            continue

        m = INCLUDE_RE.match(raw)
        if m:
            src.includes.append(m.group(1))
        m = DEFINE_RE.match(raw)
        if m:
            src.defines.add(m.group(1))
        m = CONST_RE.match(raw)
        if m:
            src.consts.add(m.group(1))
        m = GLOBALPTR_RE.match(raw)
        if m:
            src.global_ptrs.add(m.group(2))

        # ---- multi-line enum body
        if enum_pending:
            body = s
            if '}' in body:
                enum_pending = False
            head = body.split('}')[0]
            for piece in head.replace('{', '').split(','):
                name = piece.split('=')[0].strip()
                if re.fullmatch(r'[A-Za-z_]\w*', name):
                    src.enum_members.add(name)
            depth += s.count('{') - s.count('}')
            continue

        # ---- type declarations
        m = TYPE_RE.match(raw)
        if m:
            kind, name = m.group(1), m.group(2)
            src.types[name] = kind
            base = re.search(r':\s*(?:public\s+)?([A-Za-z_]\w*)', s)
            src.methods.setdefault(name, set())
            cur_class = name
            class_depth = depth
            # class may open its brace on this line
            depth += s.count('{') - s.count('}')
            continue

        m = ENUM_RE.match(raw)
        if m:
            src.types[m.group(1)] = 'enum'
            if '{' not in s:
                enum_pending = True
            else:
                head = s.split('{', 1)[1].split('}')[0]
                for piece in head.split(','):
                    name = piece.split('=')[0].strip()
                    if re.fullmatch(r'[A-Za-z_]\w*', name):
                        src.enum_members.add(name)
            depth += s.count('{') - s.count('}')
            continue

        # ---- qualified definition:  CClass::Method(
        mq = QUALIFIED_RE.match(raw)
        if mq:
            cls, meth = mq.group(1), mq.group(2)
            if cls not in ('::',):
                src.method_defs.setdefault(cls, set()).add(meth)

        # a body opening on the line after a declaration
        if pending_inline is not None:
            if s.startswith('{'):
                src.inline_bodies.add(pending_inline)
            pending_inline = None

        in_class_body = (cur_class is not None and depth == class_depth + 1)
        if in_class_body:
            mm = MEMBER_RE.match(raw)
            if mm:
                meth = mm.group(1)
                if meth not in KEYWORDS and not s.startswith(('return', 'else')):
                    src.methods.setdefault(cur_class, set()).add(meth)
                    if '= 0' in s:
                        src.interface_classes.add(cur_class)
                    # inline body detected on the same line
                    if re.search(r'\)\s*(const\s*)?\{', s):
                        src.inline_bodies.add((cur_class, meth))
                    elif s.rstrip().endswith(')'):
                        # declaration continued on the next line -> '{' check
                        pending_inline = (cur_class, meth)
        elif depth == 0:
            mf = FUNC_RE.match(raw)
            if mf:
                name = mf.group(1)
                if name not in KEYWORDS and '::' not in s:
                    src.functions.add(name)

        depth += s.count('{') - s.count('}')
        if depth < 0:
            depth = 0
        if cur_class is not None and depth <= class_depth:
            cur_class = None
            class_depth = None


def main():
    verbose = '--verbose' in sys.argv
    quiet = '--quiet' in sys.argv
    errors, warnings = [], []
    sources = {}

    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in ('.git', 'Tools', '__pycache__')]
        for fn in sorted(filenames):
            if fn.endswith(SRC_EXT):
                p = os.path.join(dirpath, fn)
                sources[p] = Source(p)

    implemented = [p for p, s in sources.items() if not s.empty]
    for p in implemented:
        parse(sources[p])

    # ---- 1..3 structural
    for p, src in sorted(sources.items()):
        if src.empty:
            continue
        for inc in src.includes:
            if not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(p), inc))):
                errors.append(f"{src.rel}: include not found: {inc}")
        if src.text.count('{') != src.text.count('}'):
            errors.append(f"{src.rel}: unbalanced braces "
                          f"({src.text.count('{')} vs {src.text.count('}')})")
        if src.text.count('(') != src.text.count(')'):
            errors.append(f"{src.rel}: unbalanced parentheses "
                          f"({src.text.count('(')} vs {src.text.count(')')})")
        if src.rel.endswith('.mqh'):
            if '#ifndef' not in src.text:
                errors.append(f"{src.rel}: missing include guard")
            elif src.text.count('#ifndef') != src.text.count('#endif'):
                errors.append(f"{src.rel}: #ifndef/#endif mismatch "
                              f"({src.text.count('#ifndef')} vs {src.text.count('#endif')})")
        if src.rel.endswith('.mqh'):
            for line in src.lines:
                if re.match(r'^\s*input\s', line):
                    errors.append(f"{src.rel}: `input` declaration in a header")

    # ---- 4 duplicate types
    owner = {}
    for p, src in sorted(sources.items()):
        for name, kind in sorted(src.types.items()):
            if name in owner and owner[name] != src.rel:
                errors.append(f"duplicate {kind} '{name}': {src.rel} vs {owner[name]}")
            owner.setdefault(name, src.rel)

    # ---- global token sets
    all_defines, all_consts, all_enum = set(), set(), set()
    all_globals, all_funcs = set(), set()
    for src in sources.values():
        all_defines |= src.defines
        all_consts |= src.consts
        all_enum |= src.enum_members
        all_globals |= src.global_ptrs
        all_funcs |= src.functions

    # ---- 8 undefined QME_* tokens
    for p, src in sorted(sources.items()):
        if src.empty:
            continue
        for tok in sorted(set(QME_TOKEN.findall(src.text))):
            if tok not in all_defines and tok not in all_consts and tok not in all_enum:
                errors.append(f"{src.rel}: undefined identifier '{tok}'")

    # ---- 5 type-like tokens never declared
    known = set(owner)
    for p, src in sorted(sources.items()):
        if src.empty:
            continue
        for name in sorted(set(re.findall(r'\b[A-Za-z_]\w*\b', src.text))):
            if not PROJECT_TYPE.match(name):
                continue
            if name in known or name in all_funcs or name in all_globals:
                continue
            warnings.append(f"{src.rel}: type-like token '{name}' is not declared anywhere")

    # ---- 6/7 methods
    for p, src in sorted(sources.items()):
        if src.empty:
            continue
        for cls, meths in sorted(src.method_defs.items()):
            if cls not in owner:
                errors.append(f"{src.rel}: definition of '{cls}::{sorted(meths)[0]}' for unknown class")
                continue
            declared = set()
            for s2 in sources.values():
                if cls in s2.types:
                    declared |= s2.methods.get(cls, set())
            for meth in sorted(meths):
                if meth not in declared and meth != cls:
                    errors.append(f"{src.rel}: '{cls}::{meth}' defined but not declared")

    declared_by_class = {}
    inline = set()
    for src in sources.values():
        for cls, meths in src.methods.items():
            declared_by_class.setdefault(cls, set()).update(meths)
        inline |= src.inline_bodies
    defined_by_class = {}
    for src in sources.values():
        for cls, meths in src.method_defs.items():
            defined_by_class.setdefault(cls, set()).update(meths)

    for cls in sorted(declared_by_class):
        iface = any(cls in s.interface_classes for s in sources.values())
        miss = []
        for meth in sorted(declared_by_class[cls]):
            if (cls, meth) in inline:
                continue
            if meth in defined_by_class.get(cls, set()):
                continue
            if meth == cls:
                continue
            miss.append(meth)
        if miss and not iface:
            errors.append(f"class {cls}: declared but never defined: {miss}")

    # ---- 10 unimplemented modules still included by someone
    included = set()
    for src in sources.values():
        for inc in src.includes:
            included.add(os.path.normpath(os.path.join(os.path.dirname(src.path), inc)))
    empties = sorted(s.rel for p, s in sources.items() if s.empty)
    for p, s in sorted(sources.items()):
        if s.empty and os.path.normpath(p) in included:
            warnings.append(f"{s.rel}: included but EMPTY (unimplemented module)")

    # ---- report
    if not quiet:
        print(f"scanned {len(sources)} files ({len(implemented)} implemented, {len(empties)} empty)")
        if verbose:
            for p, s in sorted(sources.items()):
                if s.empty:
                    continue
                print(f"  {s.rel}: types={len(s.types)} includes={len(s.includes)} "
                      f"methods={sum(len(v) for v in s.methods.values())} "
                      f"defs={sum(len(v) for v in s.method_defs.values())}")
        if empties:
            print(f"\nempty modules ({len(empties)}): " + ", ".join(empties[:12]) +
                  (" ..." if len(empties) > 12 else ""))
        if warnings:
            print(f"\n{len(warnings)} warning(s):")
            for w in warnings:
                print("  WARN  " + w)
        if errors:
            print(f"\n{len(errors)} error(s):")
            for e in errors:
                print("  ERROR " + e)
            print("\nFAILED")
            return 1
        print("\nOK: no structural errors detected (this is NOT a compilation proof)")
    return 0


if __name__ == '__main__':
    sys.exit(main())
