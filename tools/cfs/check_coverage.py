#!/usr/bin/env python3
"""Every function defined in a gated NASA .c must be defined somewhere in the HolyC translation.

WHY THIS EXISTS. The differential oracle compares TRANSCRIPTS, so it only ever sees functions the
driver calls. A function nobody calls is invisible to it: the C side links it from NASA's source,
the HolyC side simply does not have it, and 105 identical lines say nothing at all about the
omission. That is not hypothetical -- CFE_MSG_GetNextSequenceCount was missing from the
translation of cfe_msg_ccsdspri.c for four commits, while the commit that introduced it claimed
the module was complete, twice.

This is a coarse check by design: it matches on NAMES, not signatures or behaviour. Name presence
is what "did you forget one" needs, and the oracle already covers behaviour for everything the
transcript touches. A name here with a wrong body is caught by the transcript or not at all.

    tools/cfs/check_coverage.py <nasa.c> [nasa.c ...]     # HolyC side is Kernel/Cfs/cfe/*.HC
"""
import re, sys, os, glob

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# Every translated unit, cFE and OSAL alike. Scanning both rather than one directory per gate
# means a function can move between them without the check losing sight of it.
HCDIRS = [os.path.join(ROOT, "Kernel", "Cfs", "cfe"),
          os.path.join(ROOT, "Kernel", "Cfs", "osal")]

# A C function DEFINITION at file scope: a line starting in column 1 with a type, a name, an
# argument list, and an opening brace on that line or the next. `static inline` in a header is
# not our business; these are .c files.
C_DEF = re.compile(
    r'^[A-Za-z_][A-Za-z0-9_ \t\*]*?\b([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*?\)\s*$', re.M)

def c_functions(path):
    src = open(path, errors='replace').read()
    # strip comments so a prototype inside one cannot count
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    src = re.sub(r'//[^\n]*', '', src)
    out = set()
    lines = src.split('\n')
    for i, line in enumerate(lines):
        m = C_DEF.match(line + '\n')
        if not m:
            continue
        # the next non-blank line must open a body
        for nxt in lines[i+1:]:
            if nxt.strip() == '':
                continue
            if nxt.lstrip().startswith('{'):
                out.add(m.group(1))
            break
    return out

def hc_defined():
    names = set()
    files = []
    for d in HCDIRS:
        files += glob.glob(os.path.join(d, "*.HC"))
    for f in files:
        src = open(f, errors='replace').read()
        src = re.sub(r'//[^\n]*', '', src)
        for m in re.finditer(
                r'^(?:U0|I8|U8|I16|U16|I32|U32|I64|U64|F64|Bool|[A-Z][A-Za-z0-9_]*)\s+\**'
                r'([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*?\)\s*$', src, re.M):
            names.add(m.group(1))
    return names

def main(argv):
    if not argv:
        print(__doc__)
        return 2
    have = hc_defined()
    missing = []
    for c in argv:
        if not os.path.exists(c):
            print(f"FAIL cfs-coverage — no such file: {c}", file=sys.stderr)
            return 1
        for fn in sorted(c_functions(c)):
            if fn not in have:
                missing.append((os.path.basename(c), fn))
    if missing:
        print("FAIL cfs-coverage — defined in NASA's C, absent from the HolyC translation.", file=sys.stderr)
        print("  The transcript cannot see these: nothing calls them, so it stays green.", file=sys.stderr)
        for f, fn in missing:
            print(f"    {f}: {fn}", file=sys.stderr)
        return 1
    n = sum(len(c_functions(c)) for c in argv)
    print(f"cfs-coverage: {n} functions across {len(argv)} NASA sources, all present in the translation")
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
