#!/usr/bin/env python3
"""Every CFE_*_{Lock,Unlock}SharedData call carries NASA's own __func__ and __LINE__.

NASA writes the lock pair as

    CFE_ES_LockSharedData(__func__, __LINE__);

and both arguments reach the transcript: when the mutex take fails, the error line is

    CFE_ES_LockSharedData: SharedData Mutex Take Err Stat=-12,Func=CFE_ES_GetAppID,Line=748

HolyC has no __func__ and no __LINE__, so the translation writes both out as literals. That
makes them ordinary constants -- and a constant nobody compares is a constant that drifts.
This is what compares them.

IT IS NOT COSMETIC. The differential transcript is byte-identical or it fails, so a wrong line
number is a hard failure the moment any probe makes a lock fail. That is exactly how this gate
came to exist: with every ES line number written as 0, the FS mutex-failure probe produced
`Line=748` on NASA's side and `Line=0` on the translation's, and nothing else in the gate set
could see it -- check_signatures compares types, check_constants compares #defines, and a
literal argument at a call site is neither.

The two properties, per ENCLOSING FUNCTION rather than per file:

  1. the same functions contain the same sequence of lock/unlock calls
  2. each call's two literals equal NASA's __func__ (or __FILE__) and __LINE__ at that site

Grouping by the enclosing function and not by file position is deliberate, and its first run is
why: cfe_sb_priv.HC defines CFE_SB_ZeroCopyReleaseAppId before CFE_SB_CleanUpApp where NASA has
them the other way round, because HolyC needs a definition before its first call. A positional
comparison called that a mismatch. The order functions appear in is not a property of the
translation; what is inside each one is.

Property 1 is what makes property 2 meaningful: without it a file could pass by having fewer
calls that happen to carry the right numbers.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CFE = os.path.join(ROOT, 'vendor', 'cFE')
HC = os.path.join(ROOT, 'Kernel', 'Cfs', 'cfe')

# NASA source -> its translation. A file is listed here when it uses __LINE__ at all; the
# "every __LINE__ is accounted for" check below is what stops a NEW use being missed inside a
# file already in the list, and check_coverage is what stops a whole file being missed.
PAIRS = [
    ('modules/sb/fsw/src/cfe_sb_priv.c', 'cfe_sb_priv.HC'),
    ('modules/sb/fsw/src/cfe_sb_api.c', 'cfe_sb_api.HC'),
    ('modules/sb/fsw/src/cfe_sb_task.c', 'cfe_sb_task.HC'),
    ('modules/es/fsw/src/cfe_es_syslog.c', 'cfe_es_syslog.HC'),
    ('modules/es/fsw/src/cfe_es_mempool.c', 'cfe_es_mempool.HC'),
    ('modules/es/fsw/src/cfe_es_api.c', 'cfe_es_api.HC'),
]

C_CALL = re.compile(r'(CFE_(?:SB|ES)_(?:Unlock|Lock)SharedData)\s*\(\s*(__func__|__FILE__)\s*,\s*__LINE__\s*\)')
H_CALL = re.compile(r'(CFE_(?:SB|ES)_(?:Unlock|Lock)SharedData)\s*\(\s*"([^"]*)"\s*,\s*(-?\d+)\s*\)')
# A C function definition at column 1: the return type, then the name, then '('.
C_FUNC = re.compile(r'^[A-Za-z_][A-Za-z0-9_ \t*]*?\b([A-Za-z_]\w*)\s*\([^;]*$', re.M)
# A HolyC definition at column 1: U0/I32/... then the name, then '(', and NOT ending in ';'.
H_FUNC = re.compile(r'^(?:U0|U8|U16|U32|U64|I8|I16|I32|I64|Bool|F64|[A-Za-z_]\w*)\s*\**\s*'
                    r'([A-Za-z_]\w*)\s*\([^;]*$', re.M)


def enclosing(heads, offset):
    """The name of the last function definition header starting before `offset`."""
    found = '?'
    for start, name in heads:
        if start < offset:
            found = name
        else:
            break
    return found


def c_sites(path):
    """{function: [(callee, expected first literal, line)]} plus the __LINE__ count."""
    src = open(path, errors='replace').read()
    heads = [(m.start(), m.group(1)) for m in C_FUNC.finditer(src)]
    base = os.path.basename(path)
    out = {}
    for m in C_CALL.finditer(src):
        line = src[:m.start()].count('\n') + 1
        fn = enclosing(heads, m.start())
        want = base if m.group(2) == '__FILE__' else fn
        out.setdefault(fn, []).append((m.group(1), want, line))
    return out, src.count('__LINE__')


def h_sites(path):
    src = open(path, errors='replace').read()
    heads = [(m.start(), m.group(1)) for m in H_FUNC.finditer(src)]
    out = {}
    for m in H_CALL.finditer(src):
        fn = enclosing(heads, m.start())
        out.setdefault(fn, []).append((m.group(1), m.group(2), int(m.group(3))))
    return out


def main():
    rc = 0
    total = 0
    for cpath, hname in PAIRS:
        c_full = os.path.join(CFE, cpath)
        h_full = os.path.join(HC, hname)
        if not os.path.exists(c_full):
            print('FAIL cfs-locksites — NASA source missing: %s' % cpath, file=sys.stderr)
            rc = 1
            continue
        if not os.path.exists(h_full):
            print('FAIL cfs-locksites — translation missing: %s' % hname, file=sys.stderr)
            rc = 1
            continue
        cs, n_line = c_sites(c_full)
        hs = h_sites(h_full)
        # Every __LINE__ in the C must be one of these calls; a new use elsewhere is a hole.
        n_calls = sum(len(v) for v in cs.values())
        if n_line != n_calls:
            print('FAIL cfs-locksites — %s uses __LINE__ %d times but only %d are lock calls;'
                  % (os.path.basename(cpath), n_line, n_calls), file=sys.stderr)
            print('     this gate only knows how to compare the lock pair, so the rest are'
                  ' NOT compared.', file=sys.stderr)
            rc = 1
        for fn in sorted(set(cs) | set(hs)):
            cl = cs.get(fn, [])
            hl = hs.get(fn, [])
            if len(cl) != len(hl):
                print('FAIL cfs-locksites — %s: %s has %d lock call(s) in NASA and %d in the'
                      ' translation' % (hname, fn, len(cl), len(hl)), file=sys.stderr)
                rc = 1
                continue
            for i, (c, h) in enumerate(zip(cl, hl)):
                if c[0] != h[0]:
                    print('FAIL cfs-locksites — %s: %s call %d is %s in NASA, %s in the'
                          ' translation' % (hname, fn, i + 1, c[0], h[0]), file=sys.stderr)
                    rc = 1
                elif c[1] != h[1] or c[2] != h[2]:
                    print('FAIL cfs-locksites — %s: %s call %d (%s): NASA ("%s", %d),'
                          ' translation ("%s", %d)'
                          % (hname, fn, i + 1, c[0], c[1], c[2], h[1], h[2]), file=sys.stderr)
                    rc = 1
            total += len(cl)
    if rc == 0:
        print('cfs-locksites: %d shared-data lock calls carry NASA\'s own __func__ and __LINE__'
              ' across %d sources' % (total, len(PAIRS)))
    return rc


if __name__ == '__main__':
    sys.exit(main())
