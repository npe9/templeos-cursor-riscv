#!/usr/bin/env python3
"""List the UNRESOLVED host-imports in a HolyC AOT blob.

An import that nothing in the blob exports is left in a HOFYIMP1 trailer (host/aot_link.c writes
it: n*32 bytes of {u64 slot_off, char name[24]}, then u64 n, then the magic). Whoever links the
blob fills those slots. For every harness that links tests/exec/harness/oracle_out.c that is the C
runtime in bootstrap/holy_rt_names.h — which is why a kernel symbol can vanish from the image and
every behavioural test still pass. This trailer is the only place that shows it.

Note the list conflates two things in a SINGLE-unit blob: primitives the port genuinely does not
implement, and symbols that a real multi-module link resolves across units (aot_link.c patches
those and they never reach the trailer). Read a single-unit list with that in mind.

    tools/blob_imports.py blob.bin              # one name per line
    tools/blob_imports.py blob.bin --absent Abs # exit 1 if Abs IS an unresolved import
"""
import struct, sys

MAGIC = 0x31504D4959464F48  # "HOFYIMP1"

def imports(path):
    d = open(path, 'rb').read()
    if len(d) < 16:
        return []
    n, magic = struct.unpack_from('<QQ', d, len(d) - 16)
    if magic != MAGIC:
        return []                       # no trailer at all: nothing was left unresolved
    base = len(d) - 16 - n * 32
    if base < 0:
        raise SystemExit(f"{path}: trailer claims {n} imports, file is too small")
    return [d[base + k * 32 + 8: base + k * 32 + 32].split(b'\0')[0].decode('ascii', 'replace')
            for k in range(n)]

def main(argv):
    if len(argv) < 2:
        raise SystemExit(__doc__)
    names = imports(argv[1])
    # EVERY argument after --absent, not just the one right after it. The first version of this line
    # tested `argv[i-1] == '--absent'`, so `--absent Abs Sqr Floor Trunc Round` checked ONLY Abs and
    # silently ignored four names while the caller printed "5 name(s) resolved". A fail-on-purpose run
    # is what exposed it: the gate passed at a commit where Sin/Cos/Tan/ATan/Ceil were all unresolved.
    want_absent = argv[argv.index('--absent') + 1:] if '--absent' in argv else []
    if want_absent:
        bad = sorted(set(want_absent) & set(names))
        for nm in bad:
            print(f"FAIL {argv[1]} — '{nm}' is an unresolved host-import; the blob does not "
                  f"provide it and the C runtime is standing in", file=sys.stderr)
        return 1 if bad else 0
    for nm in sorted(set(names)):
        print(nm)
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv))
