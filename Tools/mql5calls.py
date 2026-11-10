#!/usr/bin/env python3
"""Rough call-arity checker for the QME MQL5 tree.

It is NOT a compiler. For every static call `CClass::Method(args)` it counts
the top-level arguments and compares them with the parameter range implied by
the method's declarations (in-class declarations provide default arguments,
out-of-line definitions provide the full parameter list). A call outside
[min required, max total] can never compile.

Usage: python3 Tools/mql5calls.py
Exit code 1 when mismatches are found, 0 otherwise.
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent


def strip_comments(s: str) -> str:
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
    return re.sub(r'//[^\n]*', '', s)


def block(s: str, brace: int) -> str:
    depth = 0
    for i in range(brace, len(s)):
        if s[i] == '{':
            depth += 1
        elif s[i] == '}':
            depth -= 1
            if depth == 0:
                return s[brace + 1:i]
    return s[brace + 1:]


def split_args(text: str):
    if text.strip() in ('', 'void'):
        return []
    args, depth, cur = [], 0, ''
    in_str = False
    prev = ''
    for ch in text:
        if ch == '"' and prev != '\\':
            in_str = not in_str
        if not in_str:
            if ch in '([{':
                depth += 1
            elif ch in ')]}':
                depth -= 1
            if ch == ',' and depth == 0:
                args.append(cur)
                cur = ''
                prev = ch
                continue
        cur += ch
        prev = ch
    if cur.strip():
        args.append(cur)
    return args


def call_args(s: str, open_idx: int):
    depth = 0
    in_str = False
    for i in range(open_idx, len(s)):
        ch = s[i]
        if ch == '"' and (i == 0 or s[i - 1] != '\\'):
            in_str = not in_str
            continue
        if in_str:
            continue
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return split_args(s[open_idx + 1:i])
    return None


files = sorted(p for p in ROOT.rglob('*') if p.suffix in ('.mqh', '.mq5'))
src = {p: strip_comments(p.read_text(errors='ignore')) for p in files}

# (class, method) -> [min required, max total] across every declaration seen
ranges = {}


def note(cls, meth, params_text):
    args = split_args(params_text)
    req = sum(1 for a in args if '=' not in a)
    key = (cls, meth)
    if key in ranges:
        lo, hi = ranges[key]
        ranges[key] = (min(lo, req), max(hi, len(args)))
    else:
        ranges[key] = (req, len(args))


for p, s in src.items():
    # in-class declarations: the class body holds "ret Method(params);" / "{...}"
    for m in re.finditer(r'\bclass\s+(C\w+)\b[^{]*\{', s):
        body = block(s, m.end() - 1)
        for d in re.finditer(r'\b(\w+)\s*\(([^()]*(?:\([^()]*\))?[^()]*)\)\s*(?:;|\{)', body):
            name = d.group(1)
            if name in ('if', 'for', 'while', 'switch', 'return', 'sizeof'):
                continue
            if name == m.group(1):
                continue  # constructor
            note(m.group(1), name, d.group(2))
    # out-of-line definitions: Class::Method(params) {
    for m in re.finditer(r'\b(C\w+)::(\w+)\s*\(', s):
        args = call_args(s, m.end() - 1)
        if args is None:
            continue
        end = s.find(')', m.end())
        if s[end + 1:end + 40].lstrip().startswith('{'):
            note(m.group(1), m.group(2), s[m.end():end])

# variable declarations per file: (position, name, type) for instance calls
DECL = re.compile(r'\b([A-Z]\w+)\s*(?:&|\*)?\s*([a-z_]\w*)\s*(?:\[[^\]]*\])?\s*(?:[;=,)]|$)')
known_types = set()
for p, s in src.items():
    for m in re.finditer(r'\bclass\s+(C\w+)\b', s):
        known_types.add(m.group(1))

problems = []
for p, s in src.items():
    decls = []
    for m in DECL.finditer(s):
        if m.group(1) in known_types:
            decls.append((m.start(), m.group(2), m.group(1)))
    decls.sort()
    # instance calls: var.Method(args)
    for m in re.finditer(r'\b([a-z_]\w*)\.(\w+)\s*\(', s):
        if m.start() > 0 and s[m.start() - 1] == '.':
            continue  # middle of a field chain
        var, meth = m.group(1), m.group(2)
        t = None
        for pos, name, typ in decls:
            if name != var:
                continue
            if pos > m.start():
                break
            t = typ
        if t is None or (t, meth) not in ranges:
            continue
        args = call_args(s, m.end() - 1)
        if args is None:
            continue
        lo, hi = ranges[(t, meth)]
        if not (lo <= len(args) <= hi):
            line = s[:m.start()].count('\n') + 1
            problems.append((str(p.relative_to(ROOT)), line, t, meth,
                             len(args), lo, hi))
    for m in re.finditer(r'\b(C\w+)::(\w+)\s*\(', s):
        key = (m.group(1), m.group(2))
        if key not in ranges:
            continue
        end = s.find(')', m.end())
        if s[end + 1:end + 40].lstrip().startswith('{'):
            continue  # the definition itself
        args = call_args(s, m.end() - 1)
        if args is None:
            continue
        lo, hi = ranges[key]
        if not (lo <= len(args) <= hi):
            line = s[:m.start()].count('\n') + 1
            problems.append((str(p.relative_to(ROOT)), line, key[0], key[1],
                             len(args), lo, hi))

seen = set()
for row in sorted(set(problems)):
    if row in seen:
        continue
    seen.add(row)
    print(f"{row[0]}:{row[1]}: {row[2]}::{row[3]} called with {row[4]} arg(s), "
          f"declared range [{row[5]}..{row[6]}]")
print(f"-- {len(seen)} arity mismatch(es); this is a heuristic, not a compiler")
sys.exit(1 if seen else 0)
