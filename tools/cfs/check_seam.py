#!/usr/bin/env python3
"""Every OS_*_Impl declaration in the translation must match NASA's, RETURN TYPE INCLUDED.

WHY THIS EXISTS. The other two checks both have a hole exactly here:

  - check_coverage.py looks at function DEFINITIONS in a .c. The _Impl functions are declared in
    os-shared-*.h and defined by a backend, so it never sees them.
  - check_signatures.py skips any name ending in _Impl for the same reason, and it compares
    only PARAMETERS -- it never looks at a return type at all.

So the 128-function seam, which is the entire specification for the hand-written backend, was
unchecked. The translation of osapi-task.c declared

    U0  OS_TaskDetach_Impl(OS_object_token_t *token);     /* wrong */
    int32 OS_TaskDetach_Impl(const OS_object_token_t *token);   /* NASA's os-shared-task.h */

and nothing in this repo would have said so. It was caught only because the C oracle happens to
include NASA's header, and the host compiler complained. A seam function the oracle does not
stub would have gone through silently, and the backend would then be written to the wrong
prototype -- the one place a mistake is most expensive, because there is no upstream to diff
against once the backend exists.

Return types are compared here even though check_signatures.py does not compare them for
ordinary functions, because for those the transcript sees a wrong return type immediately (the
driver prints rc). Nothing calls an _Impl except the shared layer, and it mostly ignores what
they return.

    tools/cfs/check_seam.py [os-shared-*.h ...]      # default: all of them
"""
import re, sys, os, glob

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HCDIRS = [os.path.join(ROOT, "Kernel", "Cfs", "osal"), os.path.join(ROOT, "Kernel", "Cfs", "cfe")]
NASA_INC = os.path.join(ROOT, "vendor", "osal", "src", "os", "shared", "inc")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_signatures import C_TYPES, H_TYPES, FN_TYPEDEF, FN_SPELLED

# A return type, normalised on top of the parameter tables. `void`/`U0` have no parameter
# meaning, so they are only needed here.
C_RET_EXTRA = [(r'\bvoid\b', ' VOID '), (r'\bbool\b', ' BOOL ')]
H_RET_EXTRA = [(r'\bU0\b', ' VOID '), (r'\bBool\b', ' BOOL ')]

# Anchored to COLUMN 1, because `return OS_GetMonotonicTime_Impl(time_struct);` also matches
# "<type> <name>(<args>);" and, being later in the file, overwrote the real declaration --
# exactly the indented-statement trap check_signatures.py hit with `if (a != b) {`.
DECL = re.compile(r'^([A-Za-z_][\w \t\*]*?)\b(\w+_Impl)[ \t]*\(([^;{]*?)\)\s*;', re.M | re.S)
# NASA declares most of the seam, but a few are `static inline` DEFINITIONS in the header
# (OS_ObjectIdToType_Impl is one). Those are just as much part of the seam.
DEFN = re.compile(r'^(?:static\s+inline\s+)([A-Za-z_][\w \t\*]*?)\b(\w+_Impl)[ \t]*'
                  r'\(([^;{]*?)\)\s*\{', re.M | re.S)


def norm_type(t, types, extra):
    for pat, rep in types + extra:
        t = re.sub(pat, rep, t)
    t = re.sub(r'\b(?!PTRNUM|PTRSZ|PTRB|TIME|PROP|TOK|NUM|SZ|SNUM|FN|VOID|BOOL\b)[A-Za-z_]\w*\b',
               ' ', t)
    return re.sub(r'[\s\*]+', '', t) or '?'


def norm_args(args, types, extra):
    if args.strip() in ('', 'void'):
        return ''
    depth, parts, cur = 0, [], ''
    for ch in args:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if ch == ',' and depth == 0:
            parts.append(cur)
            cur = ''
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    out = []
    for a in parts:
        if FN_TYPEDEF.search(a) or FN_SPELLED.search(a):
            out.append('FN')
        elif re.search(r'\[\s*\d*\s*\]', a):
            out.append('PTRB')
        else:
            out.append(norm_type(a, types, extra))
    return ','.join(out)


def decls(text, types, extra):
    text = re.sub(r'/\*.*?\*/', ' ', text, flags=re.S)
    text = re.sub(r'//[^\n]*', ' ', text)
    out = {}
    for pat in (DECL, DEFN):
        for m in pat.finditer(text):
            ret, name, args = m.group(1), m.group(2), m.group(3)
            if ret.split() and ret.split()[0] in ('return', 'if', 'while', 'for', 'else'):
                continue
            out[name] = (norm_type(ret, types, extra), norm_args(args, types, extra))
    return out


def main(argv):
    headers = argv or sorted(glob.glob(os.path.join(NASA_INC, "os-shared-*.h")))
    if not headers:
        print(f"FAIL cfs-seam — no NASA headers found under {NASA_INC}", file=sys.stderr)
        return 1
    nasa = {}
    for h in headers:
        if not os.path.exists(h):
            print(f"FAIL cfs-seam — no such file: {h}", file=sys.stderr)
            return 1
        nasa.update(decls(open(h, errors='replace').read(), C_TYPES, C_RET_EXTRA))

    mine, where = {}, {}
    for d in HCDIRS:
        for f in sorted(glob.glob(os.path.join(d, "*.HC"))):
            for k, v in decls(open(f, errors='replace').read(), H_TYPES, H_RET_EXTRA).items():
                mine[k], where[k] = v, os.path.basename(f)

    bad = []
    for name in sorted(mine):
        if name not in nasa:
            bad.append(f"    {where[name]}: {name} is declared, but NASA's headers have no such "
                       f"seam function -- check the spelling")
            continue
        if mine[name] != nasa[name]:
            n, m = nasa[name], mine[name]
            bad.append(f"    {where[name]}: {name}:\n"
                       f"        NASA        {n[0]} ({n[1]})\n"
                       f"        translation {m[0]} ({m[1]})")
    if bad:
        print("FAIL cfs-seam — an OS_*_Impl declaration does not match NASA's header.", file=sys.stderr)
        print("  This is the specification the hand-written backend will be built to, and", file=sys.stderr)
        print("  neither the coverage check nor the transcript can see a mistake in it.", file=sys.stderr)
        print("\n".join(bad), file=sys.stderr)
        return 1
    print(f"cfs-seam: {len(mine)} OS_*_Impl declarations match NASA's headers "
          f"(of {len(nasa)} in the seam)")
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
