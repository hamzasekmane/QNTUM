#!/usr/bin/env python3
"""Rough member/field checker for the QME MQL5 tree.

It is NOT a compiler. It looks for `variable.member` uses where the variable's
declared type (inferred from declarations in the same file) has no such member
in any of its base classes. Arrays and inline method bodies are handled.

Usage: python3 Tools/mql5fields.py [--verbose]
Exit code 1 when suspicious accesses are found, 0 otherwise.
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERBOSE = '--verbose' in sys.argv

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

files = sorted([p for p in ROOT.rglob('*') if p.suffix in ('.mqh', '.mq5')])
src = {p: strip_comments(p.read_text(errors='ignore')) for p in files}

types = {}
for p, s in src.items():
    for m in re.finditer(r'\b(class|struct)\s+(\w+)\s*(?::\s*public\s+(\w+))?\s*\{', s):
        kind, name, base = m.group(1), m.group(2), m.group(3)
        body = block(s, m.end() - 1)
        members, methods, member_types = set(), set(), {}
        for d in re.finditer(r'([A-Za-z_]\w*(?:\s*\*)?)\s+([A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*(?:\(([^;{}]*)\))?\s*(?:const\s*)?(?:;|\{)', body):
            nm = d.group(2)
            if nm == name:
                continue
            members.add(nm)
            member_types[nm] = d.group(1).replace('*', '').strip()
            if d.group(3) is not None or d.group(0).rstrip().endswith('{'):
                methods.add(nm)
        t = types.setdefault(name, dict(members=set(), methods=set(), member_types={}, base=base, file=str(p.relative_to(ROOT))))
        t['members'] |= members
        t['methods'] |= methods
        t['member_types'].update(member_types)
        if base:
            t['base'] = base

def members_of(t, seen=None):
    seen = seen or set()
    if t not in types or t in seen:
        return set(), set()
    seen.add(t)
    info = types[t]
    mem, meth = set(info['members']), set(info['methods'])
    if info['base']:
        bm, bmeth = members_of(info['base'], seen)
        mem |= bm
        meth |= bmeth
    return mem, meth

DECL = re.compile(r'\b([A-Z]\w+)\s*(?:&|\*)?\s*([a-z_]\w*)\s*(?:\[[^\]]*\])?\s*(?:[;=,)]|$)')

def member_type(t, member, seen=None):
    """Declared type of a data member, following base classes."""
    seen = seen or set()
    if t not in types or t in seen:
        return None
    seen.add(t)
    info = types[t]
    if member in info['member_types']:
        return info['member_types'][member]
    if info['base']:
        return member_type(info['base'], member, seen)
    return None

problems = []
for p, s in src.items():
    decls = []                                   # (position, name, type)
    for m in DECL.finditer(s):
        if m.group(1) in types:
            decls.append((m.start(), m.group(2), m.group(1)))
    decls.sort()
    for m in re.finditer(r'\b([a-z_]\w*)((?:\.[A-Za-z_]\w*(?:\([^()]*\))?)+)\b', s):
        var = m.group(1)
        chain = [c.split('(')[0] for c in m.group(2).split('.') if c]
        if m.start() > 0 and s[m.start() - 1] == '.':
            continue                             # middle of a longer chain
        t = None
        for pos, name, typ in decls:               # nearest declaration before use
            if name != var:
                continue
            if pos > m.start():
                break
            t = typ
        if not t:
            continue
        line = s[:m.start()].count('\n') + 1
        cur = t
        for depth, mem in enumerate(chain):
            mems, meths = members_of(cur)
            if not mems and not meths:
                break
            if mem in meths and mem not in mems:
                # method call: continue the chain through its declared
                # return type when it is a known type (e.g. Snapshot().login)
                nxt = member_type(cur, mem)
                if nxt in types:
                    cur = nxt
                    continue
                break
            if mem not in mems:
                problems.append((str(p.relative_to(ROOT)), line, cur, var, mem))
                break
            nxt = member_type(cur, mem)
            if nxt not in types:
                break
            cur = nxt

seen = set()
for row in sorted(set(problems)):
    if row in seen:
        continue
    seen.add(row)
    print(f"{row[0]}:{row[1]}: {row[3]} ({row[2]}) has no member '{row[4]}'")
print(f"-- {len(seen)} suspicious member access(es); this is a heuristic, not a compiler")
sys.exit(1 if seen else 0)
